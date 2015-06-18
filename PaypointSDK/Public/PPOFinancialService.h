//
//  PPOFinancialService.h
//  Paypoint
//
//  Created by Robert Nash on 19/05/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
@class PPOFinancialService
@discussion An instance of this class represents a financial service.
 */
@interface PPOFinancialService : NSObject
@property (nonatomic, copy) NSString *dateOfBirth;
@property (nonatomic, copy) NSString *surname;
@property (nonatomic, copy) NSString *accountNumber;
@property (nonatomic, copy) NSString *postCode;

/*!
@discussion A convenience method for building an NSDictionary representation of the assigned values of each property listed in this class.
@return A plist of assigned values. The NSDictionary instance will be valid for JSON serialisation using the NSJSONSerialization parser in Foundation.framework.
 */
-(NSDictionary*)jsonObjectRepresentation;

@end
