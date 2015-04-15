//
//  NetworkManager.h
//  Paypoint
//
//  Created by Robert Nash on 08/04/2015.
//  Copyright (c) 2015 Paypoint. All rights reserved.
//

#import "EndpointManager.h"
#import "Reachability.h"

#define INSTALLATION_ID @"5300065"

@interface NetworkManager : EndpointManager

+(void)getCredentialsWithCompletion:(void(^)(PPOCredentials *credentials, NSURLResponse *response, NSError *error))completion;

@end
