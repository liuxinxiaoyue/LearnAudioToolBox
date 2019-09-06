//
//  LXRecoder.m
//  LXAudioQueue
//
//  Created by admin on 2019/8/22.
//  Copyright © 2019 admin. All rights reserved.
//

#import "LXAudioRecoder.h"
#import <AVFoundation/AVFoundation.h>

static const int kNumberBuffers = 3;

@interface LXAudioRecoder () {
    // 音频队列
    AudioQueueRef queueRef;
    // buffers数量
    AudioQueueBufferRef buffers[kNumberBuffers];
    // 音频数据格式
    AudioStreamBasicDescription dataformat;
}

@property (nonatomic, assign) SInt64 currPacket;
// 录制的文件
@property (nonatomic, assign) AudioFileID mAudioFile;
// 当前录制文件的大小
@property (nonatomic, assign) UInt32 bufferBytesSize;
@end
@implementation LXAudioRecoder

- (instancetype)initWithLocalPath:(NSString *)filePath {
    if (self = [super init]) {
        [self config];
        [self setupAudio:filePath];
    }
    return self;
}

- (void)dealloc {
    AudioQueueDispose(queueRef, true);
}

/**
 *   aqData: 自定义数据
 *   inAQ: 调用回调函数的音频队列
 *   inBuffer: 装有音频数据的buffer
 *   timestamp: 当前音频数据的时间戳
 *   inNumPackets: 包数量
 *   inPacketDesc: packt的描述 如果正在录制VBR格式，音频队列会提供此参数的值，在AudioFileWritePackets时可以用到
 */
static void recoderCallBack(void *aqData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer, const AudioTimeStamp *timestamp, UInt32 inNumPackets, const AudioStreamPacketDescription *inPacketDesc) {
    NSLog(@"coom...");
    LXAudioRecoder *recoder = (__bridge LXAudioRecoder *)aqData;
    
    if (inNumPackets == 0 && recoder->dataformat.mBytesPerPacket != 0) {
        inNumPackets = inBuffer->mAudioDataByteSize / recoder->dataformat.mBytesPerPacket;
    }
    // 将音频数据写入文件
    if (AudioFileWritePackets(recoder.mAudioFile, false, inBuffer->mAudioDataByteSize, inPacketDesc, recoder.currPacket, &inNumPackets, inBuffer->mAudioData) == noErr) {
        recoder.currPacket += inNumPackets;
    }
    if (recoder.isRunning) {
        // 入队
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, NULL);
    }
}

// 获取AudioQueueBuffer大小
void deriveBufferSize(AudioQueueRef audioQueue, AudioStreamBasicDescription streamDesc, Float64 seconds, UInt32 *outBufferSize) {
    // 音频队列数据大小的上限
    static const int maxBufferSize = 0x50000;
    static const int minBufferSize = 0x4000;
    
    int maxPacketSize = streamDesc.mBytesPerPacket;
    if (maxPacketSize == 0) { // VBR
        UInt32 maxVBRPacketSize = sizeof(maxPacketSize);
        AudioQueueGetProperty(audioQueue, kAudioQueueProperty_MaximumOutputPacketSize, &maxPacketSize, &maxVBRPacketSize);
    }
    // 获取音频数据大小
    Float64 numBytesForTime = streamDesc.mSampleRate * maxPacketSize * seconds;
    if (numBytesForTime < minBufferSize) {
        *outBufferSize = minBufferSize;
    } else if (numBytesForTime > maxBufferSize) {
        *outBufferSize = maxBufferSize;
    } else {
        *outBufferSize = numBytesForTime;
    }
}

- (void)config {

    Float64 sampleRate = 44100.0;
    UInt32 channel = 2;
    // 音频格式
    dataformat.mFormatID = kAudioFormatMPEG4AAC;
    // 采样率
    dataformat.mSampleRate = sampleRate;
    // 声道数
    dataformat.mChannelsPerFrame = channel;
    UInt32 formatSize = sizeof(dataformat);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &formatSize, &dataformat);
    // 采样位数
//    dataformat.mBitsPerChannel = 16;
//    // 每个包中的字节数
//    dataformat.mBytesPerPacket = channel * sizeof(SInt16);
//    // 每个帧中的字节数
//    dataformat.mBytesPerFrame = channel * sizeof(SInt16);
//    // 每个包中的帧数
//    dataformat.mFramesPerPacket = 1;
//    // flags
//    dataformat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
}

- (void)setupAudio:(NSString *)filePath {
    self.currPacket = 0;
    
    // 创建Audio Queue
    OSStatus status = AudioQueueNewInput(&dataformat, recoderCallBack, (__bridge void *)self, NULL, NULL, 0, &queueRef);
    if (status != noErr) {
        NSLog(@"new input error");
    }
    
    // 设置音频队列数据大小
    deriveBufferSize(queueRef, dataformat, 0.5, &_bufferBytesSize);
    
    // 为Audio Queue准备指定数量的buffer
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(queueRef, self.bufferBytesSize, &buffers[i]);
        AudioQueueEnqueueBuffer(queueRef, buffers[i], 0, NULL);
    }
    
    // 创建一个音频文件
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
    NSURL *fileURL = [NSURL URLWithString:filePath];
    status = AudioFileCreateWithURL((__bridge CFURLRef)fileURL, kAudioFileCAFType, &dataformat, kAudioFileFlags_EraseFile, &_mAudioFile);

    if (status != noErr) {
        NSLog(@"create recoder file failure");
    }
    [self setupMagicCookie];
}

- (void)recoder {
    
    if (self.isRunning) {
        return;
    }
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [[AVAudioSession sharedInstance] setActive:true error:nil];
    
    OSStatus status = AudioQueueStart(queueRef, NULL);
    if (status != noErr) {
        NSLog(@"start queue failure");
        return;
    }
    _isRunning = true;
}

- (void)pause {
    if (!self.isRunning) {
        return;
    }
    OSStatus status = AudioQueuePause(queueRef);
    if (status != noErr) {
        return;
    }
    _isRunning = false;
    
    [[AVAudioSession sharedInstance] setActive:false withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)stop {
    if (self.isRunning) {
        AudioQueueStop(queueRef, true);
        _isRunning = false;
        [self setupMagicCookie];
        AudioFileClose(_mAudioFile);
        
        [[AVAudioSession sharedInstance] setActive:false withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    }
}

- (OSStatus)setupMagicCookie {
    UInt32 cookieSize = sizeof(UInt32);
    OSStatus status = AudioQueueGetPropertySize(queueRef, kAudioQueueProperty_MagicCookie, &cookieSize);
    if (status == noErr) {
        char *magicCookie = (char *)malloc(cookieSize);
        if (AudioQueueGetProperty(queueRef, kAudioQueueProperty_MagicCookie, magicCookie, &cookieSize) == noErr) {
            status = AudioFileSetProperty(_mAudioFile, kAudioFilePropertyMagicCookieData, cookieSize, magicCookie);
        }
        free(magicCookie);
    }
    return status;
}
@end
