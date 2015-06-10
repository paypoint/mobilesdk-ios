//
//  PPOPaymentManager.m
//  Paypoint
//
//  Created by Robert Nash on 07/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOPaymentManager.h"
#import "PPOBillingAddress.h"
#import "PPOPayment.h"
#import "PPOErrorManager.h"
#import "PPOCreditCard.h"
#import "PPOLuhn.h"
#import "PPOCredentials.h"
#import "PPOTransaction.h"
#import "PPOPaymentEndpointManager.h"
#import "PPORedirect.h"
#import "PPOSDKConstants.h"
#import "PPODeviceInfo.h"
#import "PPOResourcesManager.h"
#import "PPOFinancialServices.h"
#import "PPOCustomer.h"
#import "PPOCustomField.h"
#import "PPOTimeManager.h"
#import "PPOPaymentTrackingManager.h"
#import "PPORedirectManager.h"
#import "PPOValidator.h"
#import "PPOURLRequestManager.h"

@interface PPOPaymentManager () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) PPOPaymentEndpointManager *endpointManager;
@property (nonatomic, strong) NSURLSession *internalURLSession;
@property (nonatomic, strong) NSURLSession *externalURLSession;
@property (nonatomic, strong) PPODeviceInfo *deviceInfo;
@property (nonatomic, strong) PPORedirectManager *webformManager;
@property (nonatomic, strong) dispatch_queue_t r_queue;
@end

@implementation PPOPaymentManager

-(instancetype)initWithBaseURL:(NSURL*)baseURL {
    self = [super init];
    if (self) {
        _endpointManager = [[PPOPaymentEndpointManager alloc] initWithBaseURL:baseURL];
        _deviceInfo = [PPODeviceInfo new];
        NSOperationQueue *q;
        q = [NSOperationQueue new];
        q.name = @"Internal_PPO_Queue";
        q.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        _internalURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:q];
        q = [NSOperationQueue new];
        q.name = @"External_PPO_Queue";
        q.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
        _externalURLSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:q];
    }
    return self;
}

-(void)makePayment:(PPOPayment*)payment
       withTimeOut:(NSTimeInterval)timeout
    withCompletion:(void(^)(PPOOutcome *))completion {
    
    PPOOutcome *outcome;
    NSError *error;
    
    error = [PPOValidator validateBaseURL:self.endpointManager.baseURL];
    if (error) {
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome
             withCompletion:completion];
        return;
    }
    
    error = [PPOValidator validateCredentials:payment.credentials];
    if (error) {
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome
             withCompletion:completion];
        return;
    }
    
    BOOL thisPaymentUnderway = [PPOPaymentTrackingManager stateForPayment:payment] != PAYMENT_STATE_NON_EXISTENT;
    
    if (thisPaymentUnderway) {
        error = [PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorPaymentProcessing];
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome
             withCompletion:completion];
        return;
    }
    
    /*
     * PPOPaymentTrackingManager can handle multiple payments, for future proofing.
     * However, SDK forces one payment at a time (see error description PPOErrorPaymentManagerOccupied)
     */
    BOOL anyPaymentUnderway = ![PPOPaymentTrackingManager allPaymentsComplete];
    
    if (anyPaymentUnderway) {
        error = [PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorPaymentManagerOccupied];
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome
             withCompletion:completion];
        return;
    }
    
    error = [PPOValidator validatePayment:payment];
    if (error) {
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome
             withCompletion:completion];
        return;
    }
    
    NSURL *url = [self.endpointManager urlForSimplePayment:payment.credentials.installationID];
    
    NSData *body = [PPOURLRequestManager buildPostBodyWithPayment:payment
                                                   withDeviceInfo:self.deviceInfo];
    
    NSURLRequest *request = [PPOURLRequestManager requestWithURL:url
                                                      withMethod:@"POST"
                                                     withTimeout:60.0f
                                                       withToken:payment.credentials.token
                                                        withBody:body
                                                forPaymentWithID:payment.identifier];
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    if (PPO_DEBUG_MODE) {
        NSLog(@"Making payment with op ref %@", payment.identifier);
    }
    
    id completionHandler = [self networkCompletionForPayment:payment
                                       withOverallCompletion:completion];
    
    NSURLSessionDataTask *task = [self.internalURLSession dataTaskWithRequest:request
                                                            completionHandler:completionHandler];
    
    if ([PPOPaymentTrackingManager masterSessionTimeoutHasExpiredForPayment:payment]) {
        
        if (PPO_DEBUG_MODE) {
            NSLog(@"Preventing initial payment request");
        }
        
        outcome = [[PPOOutcome alloc] initWithError:[PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorMasterSessionTimedOut] forPayment:payment];
        
        [self handleOutcome:outcome
             withCompletion:completion];
        
    } else {
        __weak typeof(task) weakTask = task;
        [PPOPaymentTrackingManager appendPayment:payment
                                     withTimeout:timeout
                                    beginTimeout:YES
                                  timeoutHandler:^{
                                      [weakTask cancel];
                                  }];
        
        [task resume];
    }

}

/*
 * The implementing developer may call this if he/she wants to discover the state of a payment
 * that is currently underway, or a historic payment. This call may happen whilst the SDK is busy
 * handling a payment. The primary reason for distinguishing internal and external,
 * queries is to ensure that the master session timeout handler only cancels networking tasks that are 
 * associated with an ongoing payment. The secondary reason is so that we can assign network tasks to one 
 * of two dedicated NSURLSession instances. This allows for a cancel feature, should we want to implement 
 * that feature in the future.
 */
-(void)queryPayment:(PPOPayment*)payment
     withCompletion:(void(^)(PPOOutcome *))completion {
    
    NSError *error;
    PPOOutcome *outcome;
    
    error = [PPOValidator validateBaseURL:self.endpointManager.baseURL];
    if (error) {
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome withCompletion:completion];
        return;
    }
    
    error = [PPOValidator validateCredentials:payment.credentials];
    if (error) {
        outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
        [self handleOutcome:outcome withCompletion:completion];
        return;
    }
    
    switch ([PPOPaymentTrackingManager stateForPayment:payment]) {
            
        case PAYMENT_STATE_NON_EXISTENT: {
            
            /*
             * There may be an empty chapperone in the tracker, because the chappereone holds the payment weakly, not strongly.
             * This may happen if the entire SDK is deallocated during a payment (tracker is singleton).
             * Not essential, but worth clean up as is possible (main reason why payment is weak).
             */
            [PPOPaymentTrackingManager removePayment:payment];
            
            [self queryServerForPayment:payment
                        isInternalQuery:NO
                         withCompletion:completion];
            return;
        }
            break;
            
        case PAYMENT_STATE_READY: {
            error = [PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorPaymentProcessing];
            outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
            [self handleOutcome:outcome withCompletion:completion];
            return;
        }
            break;
            
        case PAYMENT_STATE_IN_PROGRESS: {
            error = [PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorPaymentProcessing];
            outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
            [self handleOutcome:outcome withCompletion:completion];
            return;
        }
            break;
            
        case PAYMENT_STATE_SUSPENDED: {
            error = [PPOErrorManager buildErrorForPrivateErrorCode:PPOPrivateErrorPaymentSuspendedForThreeDSecure];
            outcome = [[PPOOutcome alloc] initWithError:error forPayment:payment];
            [self handleOutcome:outcome withCompletion:completion];
            return;
        }
            break;
    }

}

/*
 * The SDK may call this method to determine the state of a payment and establish an outcome.
 * If the outcome is 'still processing' the SDK will poll this method recursively until the state changes
 * or the master session timeout timer, times out.
 */
-(void)queryServerForPayment:(PPOPayment*)payment
             isInternalQuery:(BOOL)internalQuery
              withCompletion:(void(^)(PPOOutcome *))completion {
    
    /*
     * The payment identifier is passed as a component in the url;
     */
    NSURL *url = [self.endpointManager urlForPaymentWithID:payment.identifier
                                                  withInst:payment.credentials.installationID];
    
    /*
     * The payment identifier is deliberately not passed as a header here.
     */
    NSURLRequest *request = [PPOURLRequestManager requestWithURL:url
                                                      withMethod:@"GET"
                                                     withTimeout:5.0f
                                                       withToken:payment.credentials.token
                                                        withBody:nil
                                                forPaymentWithID:nil];
    
    //We may be on self.r_queue, if we are polling
    if ([NSThread isMainThread]) {
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
        });
    }
    
    id completionHandler = [self networkCompletionForQuery:payment
                                           isInternalQuery:internalQuery
                                     withOverallCompletion:completion];
    
    /*
     * If the SDK is trying to recover, then internalQuery is set to 'YES'
     */
    NSURLSession *session = (internalQuery) ? self.internalURLSession : self.externalURLSession;
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:completionHandler];
    
    /*
     * We override the payment tracker's timeout handler so that if the SDK has progressed beyend the initial make payment phase
     * i.e. the payment has concluded with 'error' and we are querying the state. At this point, the timeout handler should cancel 
     * the query networking task that is doing the query. 
     * When the network completion handler finishes, the outcome should be 'handled' with the 'handleOutcome:' method below.
     */
    if (internalQuery) {
        __weak typeof(task) weakTask = task;
        [PPOPaymentTrackingManager overrideTimeoutHandler:^{
            [weakTask cancel];
        } forPayment:payment];
    }
    
    [task resume];

}

-(void(^)(NSData *, NSURLResponse *, NSError *))networkCompletionForQuery:(PPOPayment*)payment
                                                          isInternalQuery:(BOOL)isInternal
                                                    withOverallCompletion:(void(^)(PPOOutcome *))completion {
    
    return ^ (NSData *data, NSURLResponse *response, NSError *networkError) {
        
        id json;
        
        NSError *invalidJSON;
        
        if (data.length > 0) {
            json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&invalidJSON];
        }
        
        PPOOutcome *outcome;
        
        if (!networkError && json) {
            outcome = [[PPOOutcome alloc] initWithData:json forPayment:payment];
        } else if (networkError) {
            outcome = [[PPOOutcome alloc] initWithError:networkError forPayment:payment];
        }
        
        if (!isInternal) {
            
            if (PPO_DEBUG_MODE) {
                NSLog(@"EXTERNAL QUERY: Established error with domain: %@ with code: %li", outcome.error.domain, (long)outcome.error.code);
            }
            outcome.error = [PPOErrorManager buildCustomerFacingErrorFromError:outcome.error];
            if (PPO_DEBUG_MODE) {
                NSLog(@"EXTERNAL QUERY: Converted error to customer friendly error with domain: %@ with code: %li", outcome.error.domain, (long)outcome.error.code);
            }
            
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
            completion(outcome);
        });

    };
}

-(void(^)(NSData *, NSURLResponse *, NSError *))networkCompletionForPayment:(PPOPayment*)payment
                                                      withOverallCompletion:(void(^)(PPOOutcome *))completion {
    
    __weak typeof(self) weakSelf = self;
    
    return ^ (NSData *data, NSURLResponse *response, NSError *networkError) {
        
        id json;
        
        NSError *invalidJSON;
        
        if (data.length > 0) {
            
            json = [NSJSONSerialization JSONObjectWithData:data
                                                   options:NSJSONReadingAllowFragments
                                                     error:&invalidJSON];
            
        }
        
        PPORedirect *redirect;
        
        if ([PPORedirect requiresRedirect:json]) {
            
            redirect = [[PPORedirect alloc] initWithData:json
                                              forPayment:payment];
            
        }
                
        dispatch_async(dispatch_get_main_queue(), ^{
            
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
            
            if (invalidJSON) {
                
                [PPOPaymentTrackingManager removePayment:payment];
                completion([[PPOOutcome alloc] initWithError:[PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorServerFailure] forPayment:payment]);
                
            } else if (redirect) {
                
                [weakSelf performRedirect:redirect
                           withCompletion:completion];
                
            } else if (json) {
                
                [weakSelf handleOutcome:[[PPOOutcome alloc] initWithData:json forPayment:payment]
                         withCompletion:completion];
                
            } else if (networkError) {
                
                [weakSelf handleOutcome:[[PPOOutcome alloc] initWithError:networkError forPayment:payment]
                         withCompletion:completion];
                
            } else {
                
                [PPOPaymentTrackingManager removePayment:payment];
                completion([[PPOOutcome alloc] initWithError:[PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorUnexpected] forPayment:payment]);
                
            }
            
        });
        
    };
    
}

-(void)performRedirect:(PPORedirect*)redirect
        withCompletion:(void(^)(PPOOutcome*))completion {
    
    if (redirect.request) {
        
        __weak typeof(self) weakSelf = self;
        
        self.webformManager = [[PPORedirectManager alloc] initWithRedirect:redirect
                                                              withSession:self.internalURLSession
                                                      withEndpointManager:self.endpointManager
                                                           withCompletion:^(PPOOutcome *outcome) {
                                                               
                                                               [weakSelf handleOutcome:outcome
                                                                        withCompletion:completion];
                                                               
                                                           }];
        
        [self.webformManager startRedirect];
        
    } else {
        
        [PPOPaymentTrackingManager removePayment:redirect.payment];
        
        PPOOutcome *outcome = [[PPOOutcome alloc] initWithError:[PPOErrorManager buildErrorForPrivateErrorCode:PPOPrivateErrorProcessingThreeDSecure]
                                                     forPayment:redirect.payment];
        
        [self handleOutcome:outcome
             withCompletion:completion];
        
    }
    
}

-(void)handleOutcome:(PPOOutcome*)outcome
      withCompletion:(void(^)(PPOOutcome *))completion {
    
    BOOL isNetworkingIssue = [outcome.error.domain isEqualToString:NSURLErrorDomain];
    BOOL sessionTimedOut = isNetworkingIssue && outcome.error.code == NSURLErrorCancelled;
    BOOL isProcessingAtPaypoint = [outcome.error.domain isEqualToString:PPOPaymentErrorDomain] && outcome.error.code == PPOPaymentErrorPaymentProcessing;
    
    if ((isNetworkingIssue && !sessionTimedOut) || isProcessingAtPaypoint) {
        [self checkIfOutcomeHasChanged:outcome withCompletion:completion];
    }
    else {
        
        if (PPO_DEBUG_MODE) {
            NSLog(@"Got a conclusion. Let's dance.");
        }
        
        if (sessionTimedOut) {
            outcome.error = [PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorMasterSessionTimedOut];
        }
        
        outcome.error = [PPOErrorManager buildCustomerFacingErrorFromError:outcome.error];
        
        //We may be on self.r_queue if we were polling
        if ([NSThread isMainThread]) {
            [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
            [PPOPaymentTrackingManager removePayment:outcome.payment];
            completion(outcome);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                [PPOPaymentTrackingManager removePayment:outcome.payment];
                completion(outcome);
            });
        }
    }
    
}

-(void)checkIfOutcomeHasChanged:(PPOOutcome*)outcome
                 withCompletion:(void(^)(PPOOutcome *))completion {
    
    if (PPO_DEBUG_MODE) {
        NSLog(@"Not sure if payment made it for op ref: %@", outcome.payment.identifier);
        
        NSLog(@"Yo server, what's going on with payment for op ref %@", outcome.payment.identifier);
    }
    
    __weak typeof(self) weakSelf = self;
    
    [self queryServerForPayment:outcome.payment
                isInternalQuery:YES
                 withCompletion:^(PPOOutcome *queryOutcome) {
                     
                     if (self.r_queue == nil) {
                         self.r_queue = dispatch_queue_create("Dispatch_Recursive_Call", NULL);
                     }
                     
                     NSUInteger attemptCount = [PPOPaymentTrackingManager totalRecursiveQueryPaymentAttemptsForPayment:outcome.payment];
                     NSTimeInterval interval = [PPOPaymentTrackingManager timeIntervalForAttemptCount:attemptCount];
                     [PPOPaymentTrackingManager incrementRecurisiveQueryPaymentAttemptCountForPayment:outcome.payment];
                     
                     void(^checkAgainHandler)(void) = [weakSelf checkAgainIfOutcomeHasChanged:queryOutcome
                                                                          withBackoffInterval:interval
                                                                               withCompletion:completion];
                     
                     /*
                      * Back off period before calling again done on dedicated queue to avoid sleeping the main thread.
                      */
                     dispatch_async(self.r_queue, checkAgainHandler);
                     
                     
                 }];
    
}

-(void(^)(void))checkAgainIfOutcomeHasChanged:(PPOOutcome*)outcome
                          withBackoffInterval:(NSTimeInterval)interval
                               withCompletion:(void(^)(PPOOutcome*))completion {
    
    __weak typeof(self) weakSelf = self;
    
    return ^ {
        
        PPOPayment *payment = outcome.payment;
        
        if (PPO_DEBUG_MODE) {
            NSLog(@"Recursive query call required.");
            NSLog(@"Will sleep the recursive call thread for %f seconds", interval);
        }
        
        //Keep handler around...
        void(^timeoutHandler)(void) = [PPOPaymentTrackingManager timeoutHandlerForPayment:payment];
        
        [PPOPaymentTrackingManager overrideTimeoutHandler:^{
            //...whilst we clear the handler (just in case it fires when this thread is sleeping)...
        } forPayment:payment];
        
        sleep(interval);
        
        //...then re-insert the handler, if countdown hasn't already expired.
        if ([PPOPaymentTrackingManager masterSessionTimeoutHasExpiredForPayment:payment]) {
            
            PPOOutcome *oc = [[PPOOutcome alloc] initWithError:[PPOErrorManager buildErrorForPaymentErrorCode:PPOPaymentErrorMasterSessionTimedOut]
                                                    forPayment:payment];
            
            [weakSelf handleOutcome:oc
                     withCompletion:completion];
            
            return;
            
        }
        else {
            [PPOPaymentTrackingManager overrideTimeoutHandler:timeoutHandler forPayment:payment];
        }
        
        /*
         * This call may lead us back here recursively, if a satisfactory outcome is not met. 
         * The implementing developer master session timeout countdown will abort this recursion, 
         * if we do not get a conclusion.
         */
        [weakSelf handleOutcome:outcome
                 withCompletion:completion];
        
    };
    
}

+(BOOL)isSafeToRetryPaymentWithOutcome:(PPOOutcome *)outcome {
    
    if (!outcome) return NO;
    
    NSError *error = outcome.error;
    
    if (!error) return NO;
    
    return [PPOErrorManager isSafeToRetryPaymentWithError:error];

}

@end
