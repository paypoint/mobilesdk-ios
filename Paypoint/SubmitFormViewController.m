//
//  SubmitFormViewController.m
//  Paypoint
//
//  Created by Robert Nash on 08/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "SubmitFormViewController.h"
#import "ColourManager.h"
#import "EnvironmentManager.h"

typedef enum : NSUInteger {
    LOADING_ANIMATION_STATE_STARTING,
    LOADING_ANIMATION_STATE_IN_PROGRESS,
    LOADING_ANIMATION_STATE_ENDING,
    LOADING_ANIMATION_STATE_ENDED
} LOADING_ANIMATION_STATE;

@interface SubmitFormViewController ()
@property (nonatomic, strong) PPOPaymentManager *paymentManager;
@property (nonatomic, copy) void(^endAnimationCompletion)(void);
@end

@implementation SubmitFormViewController {
    LOADING_ANIMATION_STATE _animationState;
    BOOL _animationShouldEndAsSoonHasItHasFinishedStarting;
}

#pragma mark - Lazy Instantiation

-(PPOPaymentManager *)paymentManager {
    if (_paymentManager == nil) {
        NSURL *baseURL = [PPOBaseURLManager baseURLForEnvironment:[EnvironmentManager currentEnvironment]];
        _paymentManager = [[PPOPaymentManager alloc] initWithBaseURL:baseURL];
    }
    return _paymentManager;
}

-(void)viewDidLoad {
    [super viewDidLoad];
    
    _animationState = LOADING_ANIMATION_STATE_ENDED;
    
    PPOTransaction *transaction = [[PPOTransaction alloc] initWithCurrency:@"GBP"
                                                                withAmount:@100
                                                           withDescription:@"A description"
                                                     withMerchantReference:@"mer_txn_1234556"
                                                                isDeferred:NO];
    
    PPOBillingAddress *address = [[PPOBillingAddress alloc] initWithFirstLine:nil
                                                               withSecondLine:nil
                                                                withThirdLine:nil
                                                               withFourthLine:nil
                                                                     withCity:nil
                                                                   withRegion:nil
                                                                 withPostcode:nil
                                                              withCountryCode:nil];
    
    self.payment = [[PPOPayment alloc] initWithTransaction:transaction withCard:nil withBillingAddress:address];
    
    self.amountLabel.text = [@"£ " stringByAppendingString:self.payment.transaction.amount.stringValue];
}

-(void)blockerTapGestureRecognised:(UITapGestureRecognizer *)gesture {
    [self.paymentManager.payments cancelAllOperations];
    [self endAnimationWithCompletion:nil];
}

#pragma mark - Actions

-(IBAction)payNowButtonPressed:(UIButton *)sender {
    
    FormDetails *form = self.details;
    
    PPOCreditCard *card = [[PPOCreditCard alloc] initWithPan:form.cardNumber
                                        withSecurityCodeCode:form.cvv
                                                  withExpiry:form.expiry
                                          withCardholderName:@"Dai Jones"];
    
    self.payment.creditCard = card;
    
    PPOOutcome *outcome;
    
    outcome = [self.paymentManager validatePayment:self.payment];
    
    if (outcome) {
        
        [self handleOutcome:outcome];
        
    } else {
        
        [self attemptPayment:self.payment];
        
    }
    
}

-(void)attemptPayment:(PPOPayment*)payment {
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] == NotReachable) {
        
        [self showAlertWithMessage:@"There is no internet connection"];
        
    } else {
        
        if (_animationState == LOADING_ANIMATION_STATE_ENDED) {
            
            [self beginAnimation];
            
            __weak typeof (self) weakSelf = self;
            
            [NetworkManager getCredentialsWithCompletion:^(PPOCredentials *credentials, NSURLResponse *response, NSError *error) {
                
                PPOOutcome *outc = [weakSelf.paymentManager validateCredentials:credentials];
                
                if (outc) {
                    [weakSelf handleOutcome:outc];
                    return;
                }
                
                if (error) {
                    [weakSelf handleError:error];
                    return;
                }
                
                [weakSelf.paymentManager makePayment:payment
                                     withCredentials:credentials
                                         withTimeOut:60.0f
                                      withCompletion:^(PPOOutcome *outcome) {
                                          
                                          [weakSelf handleOutcome:outcome];
                                          
                                      }];
                
            }];
            
        }
        
    }
    
}

-(void)beginAnimation{
    
    _animationState = LOADING_ANIMATION_STATE_STARTING;
    
    NSTimeInterval duration = 1.0;
    
    self.blockerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
    self.blockerView.hidden = NO;
    
    [UIView animateWithDuration:duration/6 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        
        self.blockerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:.4];
        
        self.paypointLogoImageView.transform = CGAffineTransformMakeScale(1.9, 1.9);
        
    } completion:^(BOOL finished) {
        
        _animationState = LOADING_ANIMATION_STATE_IN_PROGRESS;
        
        self.blockerLabel.hidden = NO;
        
        [UIView animateWithDuration:duration/2 animations:^{
            self.blockerLabel.alpha = 1;
        }];
        
        [UIView animateKeyframesWithDuration:duration/2 delay:0.0 options:UIViewKeyframeAnimationOptionRepeat animations:^{
            
            [UIView addKeyframeWithRelativeStartTime:0 relativeDuration:0.5 animations:^{
                self.paypointLogoImageView.transform = CGAffineTransformMakeScale(2.2, 2.2);
            }];
            
            [UIView addKeyframeWithRelativeStartTime:0.5 relativeDuration:0.5 animations:^{
                self.paypointLogoImageView.transform = CGAffineTransformMakeScale(1.9, 1.9);
            }];
            
        } completion:^(BOOL finished) {
        }];
        
        if (_animationShouldEndAsSoonHasItHasFinishedStarting) {
            [self endAnimationWithCompletion:self.endAnimationCompletion];
        }
        
    }];
    
}

-(void)endAnimationWithCompletion:(void(^)(void))completion {
    
    self.endAnimationCompletion = completion;
    
    if (_animationState == LOADING_ANIMATION_STATE_ENDED) {
        if (self.endAnimationCompletion) self.endAnimationCompletion();
        return;
    }
    
    if (_animationState == LOADING_ANIMATION_STATE_IN_PROGRESS) {
        
        _animationState = LOADING_ANIMATION_STATE_ENDING;
        
        [self.paypointLogoImageView.layer removeAllAnimations];
        
        CALayer *currentLayer = self.paypointLogoImageView.layer.presentationLayer;
        
        self.paypointLogoImageView.layer.transform = currentLayer.transform;
        
        [UIView animateWithDuration:.6 delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{
            
            self.blockerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0];
            self.blockerLabel.alpha = 0;
            
            self.paypointLogoImageView.transform = CGAffineTransformIdentity;
            
        } completion:^(BOOL finished) {
            
            self.blockerView.hidden = YES;
            self.blockerLabel.hidden = YES;
            
            _animationState = LOADING_ANIMATION_STATE_ENDED;
            
            _animationShouldEndAsSoonHasItHasFinishedStarting = NO;
            
            if (completion) completion();
            
        }];
        
    } else {
        _animationShouldEndAsSoonHasItHasFinishedStarting = YES;
    }
    
}

-(void)handleOutcome:(PPOOutcome*)outcome {
    if (outcome.error) {
        [self handleError:outcome.error];
    } else {
        [self endAnimationWithCompletion:^{
            [self showAlertWithMessage:@"Payment Authorised"];
        }];
    }
}

-(void)handleError:(NSError*)error {
    
    NSString *message;
    
    if (error && error.domain == PPOPaypointSDKErrorDomain) {
        
        PPOErrorCode code = error.code;
        
        switch (code) {
            case PPOErrorNotInitialised: message = @"Error Code: PPOErrorNotInitialised"; break;
            case PPOErrorBadRequest: message = @"Error Code: PPOErrorBadRequest"; break;
            case PPOErrorAuthenticationFailed: message = @"Error Code: PPOErrorAuthenticationFailed"; break;
            case PPOErrorClientTokenExpired: message = @"Error Code: PPOErrorClientTokenExpired"; break;
            case PPOErrorUnauthorisedRequest: message = @"Error Code: PPOErrorUnauthorisedRequest"; break;
            case PPOErrorTransactionProcessingFailed: message = @"Error Code: PPOErrorTransactionProcessingFailed"; break;
            case PPOErrorServerFailure: message = @"Error Code: PPOErrorServerFailure"; break;
            case PPOErrorLuhnCheckFailed: message = @"Error Code: PPOErrorLuhnCheckFailed"; break;
            case PPOErrorCardExpiryDateInvalid: message = @"Error Code: PPOErrorCardExpiryDateInvalid"; break;
            case PPOErrorCardPanLengthInvalid: message = @"Error Code: PPOErrorCardPanLengthInvalid"; break;
            case PPOErrorCVVInvalid: message = @"Error Code: PPOErrorCVVInvalid"; break;
            case PPOErrorCurrencyInvalid: message = @"Error Code: PPOErrorCurrencyInvalid"; break;
            case PPOErrorPaymentAmountInvalid: message = @"Error Code: PPOErrorPaymentAmountInvalid"; break;
            case PPOErrorInstallationIDInvalid: message = @"Error Code: PPOErrorInstallationIDInvalid"; break;
            case PPOErrorSuppliedBaseURLInvalid: message = @"Error Code: PPOErrorSuppliedBaseURLInvalid"; break;
            case PPOErrorUnknown: message = @"Error Code: PPOErrorUnknown"; break;
        }
        
    } else if ([self noNetwork:error]) {
        message = @"Something went wrong with the Network. There may have been a response timeout. Please check you are connected to the internet.";
    } else {
        message = [error.userInfo objectForKey:NSLocalizedFailureReasonErrorKey];
    }
    
    if (message) {
        
        [self endAnimationWithCompletion:^{
            [self showAlertWithMessage:message];
        }];
        
    }
    
}

#pragma mark - Typical Response Error Handling

-(BOOL)noNetwork:(NSError*)error {
    return [[self noNetworkConnectionErrorCodes] containsObject:@(error.code)];
}

-(NSArray*)noNetworkConnectionErrorCodes {
    int codes[] = {
        kCFURLErrorTimedOut,
        kCFURLErrorCannotConnectToHost,
        kCFURLErrorNetworkConnectionLost,
        kCFURLErrorDNSLookupFailed,
        kCFURLErrorResourceUnavailable,
        kCFURLErrorNotConnectedToInternet,
        kCFURLErrorInternationalRoamingOff,
        kCFURLErrorCallIsActive,
        kCFURLErrorFileDoesNotExist,
        kCFURLErrorNoPermissionsToReadFile,
    };
    int size = sizeof(codes)/sizeof(int);
    NSMutableArray *array = [[NSMutableArray alloc] init];
    for (int i=0;i<size;++i){
        [array addObject:[NSNumber numberWithInt:codes[i]]];
    }
    return [array copy];
}

#pragma mark - Helpers

-(void)showAlertWithMessage:(NSString*)message {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Outcome" message:message delegate:nil cancelButtonTitle:@"Dismiss" otherButtonTitles:nil, nil];
    [alertView show];
}

@end
