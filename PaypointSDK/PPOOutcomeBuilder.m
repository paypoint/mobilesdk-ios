//
//  PPOOutcomeBuilder.m
//  Paypoint
//
//  Created by Robert Nash on 12/06/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "PPOOutcomeBuilder.h"
#import "PPOTimeManager.h"
#import "PPOSDKConstants.h"
#import "PPOCustomField.h"
#import "PPOErrorManager.h"

@interface PPOOutcomeBuilder ()
@end

@implementation PPOOutcomeBuilder

+(PPOOutcome*)outcomeWithData:(NSDictionary*)data withError:(NSError*)error forPayment:(PPOPayment *)payment {
    
    PPOOutcome *outcome = [PPOOutcome new];
    outcome.payment = payment;
    outcome.error = error;
    
    if (data) {
        [PPOOutcomeBuilder parseCustomFields:[data objectForKey:PAYMENT_RESPONSE_CUSTOM_FIELDS]
                                  forOutcome:outcome];
        
        [PPOOutcomeBuilder parseOutcome:[data objectForKey:PAYMENT_RESPONSE_OUTCOME_KEY]
                             forOutcome:outcome];
        
        [PPOOutcomeBuilder parseTransaction:[data objectForKey:TRANSACTION_RESPONSE_TRANSACTION_KEY]
                                 forOutcome:outcome];
        
        id paymentMethod = [data objectForKey:TRANSACTION_RESPONSE_METHOD_KEY];
        
        if ([paymentMethod isKindOfClass:[NSDictionary class]]) {
            [PPOOutcomeBuilder parseCard:[paymentMethod objectForKey:TRANSACTION_RESPONSE_METHOD_CARD_KEY]
                              forOutcome:outcome];
        }
    }
    
    return outcome;
}

+(void)parseCustomFields:(NSDictionary*)customFields forOutcome:(PPOOutcome*)outcome {
    
    NSArray *fieldState = [customFields objectForKey:PAYMENT_RESPONSE_CUSTOM_FIELDS_STATE];
    if ([fieldState isKindOfClass:[NSArray class]]) {
        NSMutableSet *collector = [NSMutableSet new];
        PPOCustomField *field;
        for (id object in fieldState) {
            if ([object isKindOfClass:[NSDictionary class]]) {
                field = [[PPOCustomField alloc] initWithData:object];
                [collector addObject:field];
            }
        }
        outcome.customFields = [collector copy];
    }
    
}

+(void)parseOutcome:(NSDictionary*)outcomeData forOutcome:(PPOOutcome*)outcome {
    id value;
    if ([outcomeData isKindOfClass:[NSDictionary class]]) {
        value = [outcomeData objectForKey:PAYMENT_RESPONSE_OUTCOME_REASON_KEY];
        if ([value isKindOfClass:[NSNumber class]]) {
            if (((NSNumber*)value).integerValue > 0) {
                outcome.error = [PPOErrorManager parsePaypointReasonCode:((NSNumber*)value).integerValue];
            }
        }
    }
}

+(void)parseTransaction:(NSDictionary*)transaction forOutcome:(PPOOutcome*)outcome {
    id value;
    if ([transaction isKindOfClass:[NSDictionary class]]) {
        
        PPOTimeManager *manager = [PPOTimeManager new];
        
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_AMOUNT_KEY];
        if ([value isKindOfClass:[NSNumber class]]) {
            outcome.amount = value;
        }
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_CURRENCY_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.currency = value;
        }
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_TIME_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.date = [manager dateFromString:value];
        }
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_MERCH_REF_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.merchantRef = value;
        }
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_TYPE_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.type = value;
        }
        value = [transaction objectForKey:TRANSACTION_RESPONSE_TRANSACTION_ID_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.identifier = value;
        }
    }
}

+(void)parseCard:(NSDictionary*)card forOutcome:(PPOOutcome*)outcome {
    id value;
    if ([card isKindOfClass:[NSDictionary class]]) {
        value = [card objectForKey:TRANSACTION_RESPONSE_METHOD_CARD_LAST_FOUR_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.lastFour = value;
        }
        value = [card objectForKey:TRANSACTION_RESPONSE_METHOD_CARD_USER_TYPE_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.cardUsageType = value;
        }
        value = [card objectForKey:TRANSACTION_RESPONSE_METHOD_CARD_SCHEME_KEY];
        if ([value isKindOfClass:[NSString class]]) {
            outcome.cardScheme = value;
        }
    }
}

@end