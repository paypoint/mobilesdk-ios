//
//  PPOErrorManager.h
//  Paypoint
//
//  Created by Robert Nash on 09/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOError.h"
#import "PPOOutcome.h"

@interface PPOErrorManager : NSObject

+(PPOPaymentError)parsePaypointReasonCode:(NSInteger)reasonCode;
+(NSError*)paymentErrorForCode:(PPOPaymentError)paymentErrorCode;
+(BOOL)safeToRetryPaymentWithoutRiskOfDuplication:(NSError*)error;

@end
