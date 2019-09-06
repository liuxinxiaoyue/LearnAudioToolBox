//
//  LXPlayer.m
//  LXAudioQueue
//
//  Created by admin on 2019/8/22.
//  Copyright © 2019 admin. All rights reserved.
//

#import "LXAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

static const int kNumberBuffers = 3;

@interface LXAudioPlayer () {
    AudioStreamBasicDescription   dataFormat;
    AudioQueueRef                 queueRef;
    AudioQueueBufferRef           mBuffers[kNumberBuffers];
}

@property (nonatomic, assign) AudioFileID mAudioFile;
@property (nonatomic, assign) UInt32 bufferByteSize;
@property (nonatomic, assign) SInt64 mCurrentPacket;
@property (nonatomic, assign) UInt32 mPacketsToRead;
@property (nonatomic, assign) AudioStreamPacketDescription *mPacketDescs;
@property (nonatomic, assign) bool isRunning;
@end

@implementation LXAudioPlayer


static void playCallback(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer) {
    LXAudioPlayer *player = (__bridge LXAudioPlayer *)aqData;
    UInt32 numBytesReadFromFile = player.bufferByteSize;
    UInt32 numPackets = player.mPacketsToRead;
    AudioFileReadPacketData(player.mAudioFile, false, &numBytesReadFromFile, player.mPacketDescs, player.mCurrentPacket, &numPackets, inBuffer->mAudioData);
    if (numPackets > 0) {
        inBuffer->mAudioDataByteSize = numBytesReadFromFile;
        player.mCurrentPacket += numPackets;
        AudioQueueEnqueueBuffer(player->queueRef, inBuffer, player.mPacketDescs ? numPackets : 0, player.mPacketDescs);
    } else {
        NSLog(@"play end");
        AudioQueueStop(player->queueRef, false);
        player.isRunning = false;
    }
}

/** 计算音频队列数据
 *
 *  maxPacketSize 当前播放音频文件最大数据包大小 AudioFileGetProperty查询 kAudioFilePropertyPacketSizeUpperBound
 *  seconds 采样时间
 *  outBufferSize 每个音频数据的大小
 *  outNumPacketsToRead 每次从音频播放回调中读取的音频数据包数
 */
void playBufferSize(AudioStreamBasicDescription basicDesc, UInt32 maxPacketSize, Float64 seconds, UInt32 *outBufferSize, UInt32 *outNumPacketsToRead) {
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000;

    if (basicDesc.mFramesPerPacket != 0) {
        Float64 numPacketsForTime = basicDesc.mSampleRate / basicDesc.mFramesPerPacket * seconds;
        *outBufferSize = numPacketsForTime * maxPacketSize;
    } else {
        *outBufferSize = maxBufferSize > maxPacketSize ? maxBufferSize : maxPacketSize;
    }

    if (*outBufferSize > maxBufferSize && *outBufferSize > maxPacketSize) {
        *outBufferSize = maxBufferSize;
    } else {
        if (*outBufferSize < minBufferSize) {
            *outBufferSize = minBufferSize;
        }
    }
    *outNumPacketsToRead = *outBufferSize / maxPacketSize;
}

- (instancetype)initWithLocalPath:(NSString *)filePath {
    if (self = [super init]) {
        [self setupPlayer:filePath];
    }
    return self;
}

- (void)dealloc {
    AudioFileClose(_mAudioFile);
    AudioQueueDispose(queueRef, true);
    if (_mPacketDescs) {
        free(_mPacketDescs);
    }
}

- (void)setupPlayer:(NSString *)filePath {
    // 打开文件
    NSURL *fileURL = [NSURL URLWithString:filePath];
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)fileURL, kAudioFileReadPermission, kAudioFileCAFType, &_mAudioFile);
    if (status != noErr) {
        NSLog(@"open file error");
    }
    
    // 获取文件格式
    UInt32 dataFromatSize = sizeof(dataFormat);
    AudioFileGetProperty(_mAudioFile, kAudioFilePropertyDataFormat, &dataFromatSize, &dataFormat);
    
    // 创建播放音频队列
    status = AudioQueueNewOutput(&dataFormat, playCallback, (__bridge void *)self, CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &queueRef);
    if (status != noErr) {
        NSLog(@"create play queue error");
    }
    
    // 设置音频队列大小
    UInt32 maxPacketSize;
    UInt32 propertySize = sizeof(maxPacketSize);
    status = AudioFileGetProperty(_mAudioFile, kAudioFilePropertyPacketSizeUpperBound, &propertySize, &maxPacketSize);
    playBufferSize(dataFormat, maxPacketSize, 0.5, &_bufferByteSize, &_mPacketsToRead);
    
    _mCurrentPacket = 0;
    
    // 为数据包描述数组分配内存
    bool isFormatVBR = dataFormat.mBytesPerPacket == 0 || dataFormat.mFramesPerPacket == 0;
    if (isFormatVBR) {
        _mPacketDescs = (AudioStreamPacketDescription *)malloc(_mPacketsToRead * sizeof(AudioStreamPacketDescription));
    } else {
        _mPacketDescs = NULL;
    }
    
    [self setupMagicCookie];
    
    // 分配音频队列
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(queueRef, _bufferByteSize, &mBuffers[i]);
        playCallback((__bridge void *)self, queueRef, mBuffers[i]);
    }
    
    // 设置音量 0 ~ 1
    Float32 gain = 1.0;
    AudioQueueSetParameter(queueRef, kAudioQueueParam_Volume, gain);
}

- (void)setupMagicCookie {
    // magic cookie
    UInt32 cookieSize = sizeof(UInt32);
    if (AudioFileGetPropertyInfo(_mAudioFile, kAudioFilePropertyMagicCookieData, &cookieSize, NULL) == noErr && cookieSize) {
        char *magicCookie = (char *)malloc(cookieSize);
        if (AudioFileGetProperty(_mAudioFile, kAudioFilePropertyMagicCookieData, &cookieSize, magicCookie) == noErr) {
            AudioQueueSetProperty(queueRef, kAudioQueueProperty_MagicCookie, magicCookie, cookieSize);
        }
        free(magicCookie);
    }
}

- (void)play {
    if (self.isRunning) {
        return;
    }
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    //[[AVAudioSession sharedInstance] setActive:YES error:nil];
    [[AVAudioSession sharedInstance] setActive:true withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    
    OSStatus status = AudioQueueStart(queueRef, NULL);
    if (status != noErr) {
        NSLog(@"play error");
        return;
    }
    self.isRunning = true;
}

- (void)pause {
    if (!self.isRunning) {
        return;
    }
    OSStatus status = AudioQueuePause(queueRef);
    if (status == noErr) {
        self.isRunning = false;

        [[AVAudioSession sharedInstance] setActive:false withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
}

- (void)stop {
    if (self.isRunning) {
        self.isRunning = false;
        AudioQueueStop(queueRef, true);
        
        [[AVAudioSession sharedInstance] setActive:false withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
}

- (BOOL)isPlaying {
    return self.isRunning;
}
@end
