//
//  LXPlayer.h
//  LXAudioQueue
//
//  Created by admin on 2019/8/22.
//  Copyright © 2019 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LXAudioPlayer : NSObject

@property (nonatomic, assign, readonly) BOOL isPlaying;

- (instancetype)initWithLocalPath:(NSString *)filePath;

- (void)play;

- (void)pause;

- (void)stop;
@end

NS_ASSUME_NONNULL_END
