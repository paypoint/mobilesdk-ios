//
//  PPOPaymentManager.m
//  Paypoint
//
//  Created by Robert Nash on 07/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOPaymentManager.h"
#import "PPOEndpointManager.h"
#import "PPOCreditCard.h"
#import "PPOCredentials.h"
#import "PPOTransaction.h"
#import "PPOBillingAddress.h"
#import "PPOErrorManager.h"
#import "PPOLuhn.h"

@interface PPOPaymentManager () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) NSOperationQueue *payments;
@end

@implementation PPOPaymentManager

-(instancetype)initWithCredentials:(PPOCredentials*)credentials withDelegate:(id<PPOPaymentManagerDelegate>)delegate {
    self = [super init];
    if (self) {
        _credentials = credentials;
        _delegate = delegate;
    }
    return self;
}

-(void)makePaymentWithTransaction:(PPOTransaction*)transaction forCard:(PPOCreditCard*)card withBillingAddress:(PPOBillingAddress*)billingAddress withTimeOut:(CGFloat)timeout {
    
    NSError *validationError = [self validateTransaction:transaction withCard:card];
    
    if (validationError) { [self.delegate paymentFailed:validationError]; return; }
    
    NSURL *url = [PPOEndpointManager simplePayment:self.credentials.installationID];
    
    NSMutableURLRequest *request = [self mutableJSONPostRequest:url
                                                    withTimeOut:timeout];
    
    [request setValue:[self authorisation:self.credentials] forHTTPHeaderField:@"Authorization"];
    
    NSData *data = [self buildPostBodyWithTransaction:transaction
                                             withCard:card
                                          withAddress:billingAddress];
    
    [request setHTTPBody:data];
    
    __weak typeof (self) weakSelf = self;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                          delegate:self
                                                     delegateQueue:self.payments];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                                                
                                                if (error) {
                                                    
                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                        [weakSelf.delegate paymentFailed:error];
                                                    });
                                                    
                                                    return;
                                                }
                                                
                                                [weakSelf parsePaypointData:data];
                                                
                                            }];
    
    [task resume];
}

-(NSError*)validateTransaction:(PPOTransaction*)transaction withCard:(PPOCreditCard*)card {
    
    NSString *strippedValue;
    
    strippedValue = [card.pan stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    
    if (strippedValue.length < 15 || strippedValue.length > 19) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorCardPanLengthInvalid
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The supplied payment card Pan length is invalid", @"Failure message for a card validation check")
                                          }
                ];
        
    }
    
    if (![PPOLuhn validateString:strippedValue]) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorLuhnCheckFailed
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The supplied payment card failed Luhn validation", @"Failure message for a card validation check")
                                          }
                ];
    }
    
    strippedValue = [card.cvv stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length < 3 || strippedValue.length > 4) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorCVVInvalid
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The supplied payment card CVV is invalid", @"Failure message for a card validation check")
                                          }
                ];
        
    }
    
    strippedValue = [card.expiry stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length != 4) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorCardExpiryDateInvalid
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The supplied payment card expiry date is invalid", @"Failure message for a card validation check")
                                          }
                ];
    }
    
    strippedValue = [transaction.currency stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length == 0) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorCurrencyInvalid
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The specified currency is invalid", @"Failure message for a transaction validation check")
                                          }
                ];
    }
    
    if (transaction.amount == nil || transaction.amount.floatValue <= 0.0) {
        
        return [NSError errorWithDomain:PPOPaypointSDKErrorDomain
                                   code:PPOErrorPaymentAmountInvalid
                               userInfo:@{
                                          NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"The specified payment amount is invalid", @"Failure message for a transaction validation check")
                                          }
                ];
        
    }
    
    return nil;
}

-(void)parsePaypointData:(NSData *)data {
    
    NSError *paypointError;
    PPOOutcome *outcome = [PPOErrorManager determineError:&paypointError inResponse:data];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (paypointError) {
            [self.delegate paymentFailed:paypointError];
        } else {
            [self.delegate paymentSucceeded:outcome.reasonMessage];
        }
    });
}

-(NSMutableURLRequest*)mutableJSONPostRequest:(NSURL*)url withTimeOut:(CGFloat)timeout {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:timeout];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    return request;
}

-(NSString*)authorisation:(PPOCredentials*)credentials {
    return [NSString stringWithFormat:@"Bearer %@", credentials.token];
}

-(NSData*)buildPostBodyWithTransaction:(PPOTransaction*)transaction withCard:(PPOCreditCard*)card withAddress:(PPOBillingAddress*)address {
    
    id value;
    id t;
    id c;
    id a;
    
    value = [transaction jsonObjectRepresentation];
    t = (value) ?: [NSNull null];
    value = [card jsonObjectRepresentation];
    c = (value) ?: [NSNull null];
    value = [address jsonObjectRepresentation];
    a = (value) ?: [NSNull null];
    
    id object = @{
                  @"transaction": t,
                  @"paymentMethod": @{
                                    @"card": c,
                                    @"billingAddress": a
                                    }
                  };
    
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
}

-(NSOperationQueue *)payments {
    if (_payments == nil) {
        _payments = [NSOperationQueue new];
        _payments.name = @"Payments_Queue";
        _payments.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    }
    return _payments;
}

#pragma mark - NSURLSessionDataTaskProtocol

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    NSLog(@"%@ NSURLSession didReceiveChallenge: %@", [self class], challenge);
    
    //    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
    //    {
    //        SecTrustResultType result;
    //        //This takes the serverTrust object and checkes it against your keychain
    //        SecTrustEvaluate(challenge.protectionSpace.serverTrust, &result);
    //
    //        //If allow invalid certs, end here
    //        //completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    //
    //        //When testing this against a trusted server I got kSecTrustResultUnspecified every time. But the other two match the description of a trusted server
    //        if(result == kSecTrustResultProceed ||  result == kSecTrustResultUnspecified){
    //            completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    //        }
    //        else {
    //            //Asks the user for trust
    //            if (YES) {
    //                //May need to add a method to add serverTrust to the keychain like Firefox's "Add Excpetion"
    //                completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
    //            }
    //            else {
    //                [[challenge sender] cancelAuthenticationChallenge:challenge];
    //            }
    //        }
    //    }
    //    else if ([[challenge protectionSpace] authenticationMethod] == NSURLAuthenticationMethodDefault) {
    //        NSURLCredential *newCredential = [NSURLCredential credentialWithUser:@"" password:@"" persistence:NSURLCredentialPersistenceNone];
    //        completionHandler(NSURLSessionAuthChallengeUseCredential, newCredential);
    //    }
    
    completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust]);
}

@end
