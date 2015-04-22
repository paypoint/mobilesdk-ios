//
//  PPOBaseURLManager.m
//  Paypoint
//
//  Created by Robert Nash on 17/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOPaymentBaseURLManager.h"

@implementation PPOPaymentBaseURLManager

+(NSURL*)baseURLForEnvironment:(PPOEnvironment)environment {
    
    switch (environment) {
        case PPOMerchantIntegrationTestingEnvironment:
            return [NSURL URLWithString:@"http://10.104.113.14:5000/mobileapi"];
            break;
            
        default:
            return nil;
            break;
    }
    
}

@end