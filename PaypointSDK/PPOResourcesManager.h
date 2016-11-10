//
//  PPOResourcesManager.h
//  Pay360
//
//  Created by Robert Nash on 12/05/2015.
//  Copyright (c) 2016 Pay360 by Capita. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface PPOResourcesManager : NSObject

+(NSBundle*)resources;
+(NSDictionary*)infoPlist;
+(NSDictionary*)frameworkVersion;
+(NSNumber*)frameworkBuild;

@end
