//
//  LXAudioRecorder.h
//  LXAudioUnit_AAC
//
//  Created by admin on 2019/9/11.
//  Copyright © 2019 admin. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LXAudioRecorder : NSObject

- (instancetype)initWithURL:(NSURL *)fileURL;

- (void)record;

- (void)stop;
@end

NS_ASSUME_NONNULL_END
