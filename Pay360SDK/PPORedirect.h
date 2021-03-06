//
//  PPORedirect.h
//  Pay360
//
//  Created by Robert Nash on 14/05/2015.
//  Copyright (c) 2016 Capita Plc. All rights reserved.
//

#import "PPOPayment.h"

@interface PPORedirect : NSObject
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, strong) NSNumber *sessionTimeoutTimeInterval;
@property (nonatomic, strong) NSNumber *delayTimeInterval;
@property (nonatomic, strong) NSURL *termURL;
@property (nonatomic, strong) NSString *transactionID;
@property (nonatomic, strong) PPOPayment *payment;
@property (nonatomic, strong) NSData *threeDSecureResumeBody;

-(instancetype)initWithData:(NSDictionary*)data
                 forPayment:(PPOPayment*)payment;

+(BOOL)requiresRedirect:(id)json;

@end
