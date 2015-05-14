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
#import "PPOWebViewController.h"
#import "PPORedirect.h"

@interface PPOPaymentManager () <NSURLSessionTaskDelegate, PPOWebViewControllerDelegate>
@property (nonatomic, strong, readwrite) NSURL *baseURL;
@property (nonatomic, strong) PPOPaymentEndpointManager *endpointManager;
@property (nonatomic, copy) void(^outcomeCompletion)(PPOOutcome *outcome, NSError *error);
@property (nonatomic) CGFloat timeout;
@property (nonatomic, strong) PPOCredentials *credentials;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, readwrite) NSOperationQueue *payments;
@property (nonatomic, strong) PPOWebViewController *webController;
@end

@implementation PPOPaymentManager {
    BOOL _preventShowWebView;
}

-(instancetype)initWithBaseURL:(NSURL*)baseURL {
    self = [super init];
    if (self) {
        _baseURL = baseURL;
    }
    return self;
}

-(PPOPaymentEndpointManager *)endpointManager {
    if (_endpointManager == nil) {
        _endpointManager = [PPOPaymentEndpointManager new];
    }
    return _endpointManager;
}

-(NSOperationQueue *)payments {
    if (_payments == nil) {
        _payments = [NSOperationQueue new];
        _payments.name = @"Payments_Queue";
        _payments.maxConcurrentOperationCount = NSOperationQueueDefaultMaxConcurrentOperationCount;
    }
    return _payments;
}

-(NSURLSession *)session {
    if (_session == nil) {
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:self.payments];
    }
    return _session;
}

-(void)makePayment:(PPOPayment*)payment withCredentials:(PPOCredentials*)credentials withTimeOut:(CGFloat)timeout withCompletion:(void(^)(PPOOutcome *outcome, NSError *paymentFailure))completion {
    
    NSError *invalid = [PPOPaymentValidator validateCredentials:credentials validateBaseURL:self.baseURL validatePayment:payment];
    
    if (invalid) {
        completion(nil, invalid);
        return;
    }
    
    NSURL *url = [self.endpointManager simplePayment:credentials.installationID withBaseURL:self.baseURL];
    NSData *data = [self buildPostBodyWithTransaction:payment.transaction withCard:payment.card withAddress:payment.address];
    NSString *authorisation = [self authorisation:credentials];
    
    NSMutableURLRequest *request = [self mutableJSONPostRequest:url withTimeOut:timeout];
    [request setValue:authorisation forHTTPHeaderField:@"Authorization"];
    [request setHTTPBody:data];
    

    self.outcomeCompletion = completion;
    self.timeout = timeout;
    self.credentials = credentials;
    
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        
        id json;
        NSError *invalidJSON;
        
        if (data.length > 0) {
            json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&invalidJSON];
        }
        
        if (invalidJSON) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                completion(nil, [PPOErrorManager errorForCode:PPOErrorServerFailure]);
            });
            return;
        }
        
        id value = [json objectForKey:@"threeDSRedirect"];
        if ([value isKindOfClass:[NSDictionary class]]) {
            PPORedirect *redirect = [[PPORedirect alloc] initWithData:value];
            if (redirect.request) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.webController = [[PPOWebViewController alloc] initWithRedirect:redirect withDelegate:self];
                    
                    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                    CGFloat width = [UIScreen mainScreen].bounds.size.width;
                    CGFloat height = [UIScreen mainScreen].bounds.size.height;
                    self.webController.view.frame = CGRectMake(-height, -width, width, height);
                    [[[UIApplication sharedApplication] keyWindow] addSubview:self.webController.view];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                    completion(nil, [PPOErrorManager errorForCode:PPOErrorProcessingThreeDSecure]);
                });
            }
            return;
        }
        
        if (json) {
            NSError *error;
            PPOOutcome *outcome = [[PPOOutcome alloc] initWithData:json];
            if (outcome.isSuccessful == NO) {
                PPOErrorCode code = [PPOErrorManager errorCodeForReasonCode:outcome.reasonCode.integerValue];
                error = [PPOErrorManager errorForCode:code];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                completion(outcome, error);
            });
        }
        
        if (networkError) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                completion(nil, networkError);
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                completion(nil, [PPOErrorManager errorForCode:PPOErrorUnknown]);
            });
        }
        
    }];
    
    [task resume];
    
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

-(void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler {
    
    NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

-(void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    
    NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
    completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
}

#pragma mark - PPOWebViewController

-(void)webViewController:(PPOWebViewController *)controller completedWithPaRes:(NSString *)paRes forTransactionWithID:(NSString *)transID {
    
    _preventShowWebView = YES;
    
    if ([[UIApplication sharedApplication] keyWindow] == self.webController.view.superview) {
        [self.webController.view removeFromSuperview];
    }
    
    id data;
    if (paRes) {
        NSDictionary *dictionary = @{@"threeDSecureResponse": @{@"pares":paRes}};
        data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:nil];
    }
    
    NSURLSessionDataTask *task;
    NSURL *url = [self.endpointManager resumePaymentWithInstallationID:INSTALLATION_ID transactionID:transID withBaseURL:self.baseURL];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:self.timeout];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPMethod:@"POST"];
    [request setValue:[self authorisation:self.credentials] forHTTPHeaderField:@"Authorization"];
    [request setHTTPBody:data];
    
    task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        
        if (((NSHTTPURLResponse*)response).statusCode == 200) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
            PPOOutcome *outcome = [[PPOOutcome alloc] initWithData:json];
            if (outcome.isSuccessful == NO) {
                PPOErrorCode code = [PPOErrorManager errorCodeForReasonCode:outcome.reasonCode.integerValue];
                error = [PPOErrorManager errorForCode:code];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                id controller = [[UIApplication sharedApplication] keyWindow].rootViewController.presentedViewController;
                if (controller && controller == self.webController.navigationController) {
                    [[[UIApplication sharedApplication] keyWindow].rootViewController dismissViewControllerAnimated:YES completion:^{
                        self.outcomeCompletion(outcome, error);
                        _preventShowWebView = NO;
                    }];
                } else {
                    self.outcomeCompletion(outcome, error);
                    _preventShowWebView = NO;
                }
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                id controller = [[UIApplication sharedApplication] keyWindow].rootViewController.presentedViewController;
                if (controller && controller == self.webController.navigationController) {
                    [[[UIApplication sharedApplication] keyWindow].rootViewController dismissViewControllerAnimated:YES completion:^{
                        self.outcomeCompletion(nil, [PPOErrorManager errorForCode:PPOErrorUnknown]);
                        _preventShowWebView = NO;
                    }];
                } else {
                    self.outcomeCompletion(nil, [PPOErrorManager errorForCode:PPOErrorUnknown]);
                    _preventShowWebView = NO;
                }
            });
        }
        
    }];
    
    [task resume];
    
}

-(void)webViewControllerDelayShowTimeoutExpired:(PPOWebViewController *)controller {
    if (!_preventShowWebView) {
        [self.webController.view removeFromSuperview];
        UINavigationController *navCon = [[UINavigationController alloc] initWithRootViewController:self.webController];
        [[[UIApplication sharedApplication] keyWindow].rootViewController presentViewController:navCon animated:YES completion:nil];
    }
}

-(void)webViewControllerSessionTimeoutExpired:(PPOWebViewController *)webController {
    [self handleError:[PPOErrorManager errorForCode:PPOErrorThreeDSecureTimedOut]
        webController:webController];
}

-(void)webViewController:(PPOWebViewController *)webController failedWithError:(NSError *)error {
    [self handleError:error
        webController:webController];
}

-(void)webViewControllerUserCancelled:(PPOWebViewController *)webController {
    [self handleError:[PPOErrorManager errorForCode:PPOErrorUserCancelled]
        webController:webController];
}

-(void)handleError:(NSError *)error webController:(PPOWebViewController *)webController {
    _preventShowWebView = YES;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
    id controller = [[UIApplication sharedApplication] keyWindow].rootViewController.presentedViewController;
    if (controller && controller == webController.navigationController) {
        [[[UIApplication sharedApplication] keyWindow].rootViewController dismissViewControllerAnimated:YES completion:^{
            self.outcomeCompletion(nil, error);
            _preventShowWebView = NO;
        }];
    } else {
        self.outcomeCompletion(nil, error);
        _preventShowWebView = NO;
    }
}

@end

@implementation PPOPaymentValidator

+(NSError*)validateCredentials:(PPOCredentials*)credentials validateBaseURL:(NSURL*)baseURL validatePayment:(PPOPayment*)payment {
    
    NSError *er;
    
    er = [self validateCredentials:credentials];
    
    if (er) {
        return er;
    }
    
    er = [self validatePayment:payment];
    
    if (er) {
        return er;
    }
    
    er = [self validateBaseURL:baseURL];
    
    if (er) {
        return er;
    }
    
    return nil;
}

+(NSError*)validatePayment:(PPOPayment*)payment {
    
    return [self validateTransaction:payment.transaction
                            withCard:payment.card];
    
}

+(NSError*)validateBaseURL:(NSURL*)baseURL {
    if (!baseURL) {
        return [PPOErrorManager errorForCode:PPOErrorSuppliedBaseURLInvalid];
    }
    return nil;
}

+(NSError*)validateCredentials:(PPOCredentials*)credentials {
    
    if (!credentials) {
        return [PPOErrorManager errorForCode:PPOErrorCredentialsNotFound];
    }
    
    if (!credentials.token || credentials.token.length == 0) {
        return [PPOErrorManager errorForCode:PPOErrorClientTokenInvalid];
    }
    
    if (!credentials.installationID || credentials.installationID.length == 0) {
        return [PPOErrorManager errorForCode:PPOErrorInstallationIDInvalid];
    }
    
    return nil;
}

+(NSError*)validateTransaction:(PPOTransaction*)transaction withCard:(PPOCreditCard*)card {
    
    NSString *strippedValue;
    
    strippedValue = [card.pan stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue.length < 13 || strippedValue.length > 19) {
        return [PPOErrorManager errorForCode:PPOErrorCardPanLengthInvalid];
    }
    
    if (![PPOLuhn validateString:strippedValue]) {
        return [PPOErrorManager errorForCode:PPOErrorLuhnCheckFailed];
    }
    
    strippedValue = [card.cvv stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length < 3 || strippedValue.length > 4) {
        return [PPOErrorManager errorForCode:PPOErrorCVVInvalid];
    }
    
    strippedValue = [card.expiry stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length != 4) {
        
        return [PPOErrorManager errorForCode:PPOErrorCardExpiryDateInvalid];
    }
    
    strippedValue = [transaction.currency stringByReplacingOccurrencesOfString:@" " withString:@""];
    
    if (strippedValue == nil || strippedValue.length == 0) {
        return [PPOErrorManager errorForCode:PPOErrorCurrencyInvalid];
    }
    
    if (transaction.amount == nil || transaction.amount.floatValue <= 0.0) {
        return [PPOErrorManager errorForCode:PPOErrorPaymentAmountInvalid];
    }
    
    return nil;
}

@end
