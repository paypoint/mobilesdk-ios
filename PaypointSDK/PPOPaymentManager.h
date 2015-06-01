//
//  PPOPaymentManager.h
//  Paypoint
//
//  Created by Robert Nash on 07/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOError.h"
#import "PPOOutcome.h"

@class PPOPayment;
@class PPOCredentials;
@class PPOTransaction;
@class PPOBillingAddress;
@class PPOCreditCard;

@interface PPOPaymentManager : NSObject

/*!
 * @discussion A required initialiser for setting the baseURL.
 * @param baseURL The baseURL to be used for all subsequent payments made using an instance of this class.
 * @return An instance of PPOPaymentManager
 */
-(instancetype)initWithBaseURL:(NSURL*)baseURL;

/*!
 * @discussion Makes a simple payment
 * @param payment Details of the current payment.
 * @param credentials Credentials for making a payment.
 * @param timeout 60.0 seconds is the minimum recommended, to lower the risk of failed payments.
 * @param completion The result of the payment.
 * @warning Inspect the completion block error domain PPOPaypointSDKErrorDomain for paypoint specific error cases. Each error code can be found within PPOError.h
 */
-(void)makePayment:(PPOPayment*)payment
   withCredentials:(PPOCredentials*)credentials
       withTimeOut:(NSTimeInterval)timeout
    withCompletion:(void(^)(PPOOutcome *outcome, NSError *paymentFailure))completion;

-(void)paymentStatus:(PPOPayment*)payment
     withCredentials:(PPOCredentials*)credentials
      withCompletion:(void(^)(PPOOutcome *outcome, NSError *networkError))completion;

@end
