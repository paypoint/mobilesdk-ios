//
//  PPOWebFormDelegate.h
//  Paypoint
//
//  Created by Robert Nash on 01/06/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import <Foundation/Foundation.h>

@class PPORedirect;
@class PPOOutcome;
@class PPOPaymentEndpointManager;
@class PPOCredentials;
@class PPORedirectManager;

@interface PPORedirectManager : NSObject

-(instancetype)initWithRedirect:(PPORedirect*)redirect
                    withSession:(NSURLSession*)session
            withEndpointManager:(PPOPaymentEndpointManager*)endpointManager
                 withCompletion:(void(^)(PPOOutcome *outcome))completion;

-(void)startRedirect;

@end