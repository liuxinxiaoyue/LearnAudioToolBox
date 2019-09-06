//
//  LXRecoder.h
//  LXAudioQueue
//
//  Created by admin on 2019/8/22.
//  Copyright © 2019 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LXAudioRecoder : NSObject

@property (nonatomic, assign, readonly) BOOL isRunning;

- (instancetype)initWithLocalPath:(NSString *)filePath;

- (void)recoder;

- (void)pause;

- (void)stop;
@end

NS_ASSUME_NONNULL_END
