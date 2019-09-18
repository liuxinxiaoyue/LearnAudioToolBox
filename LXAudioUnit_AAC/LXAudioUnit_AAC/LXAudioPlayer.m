//
//  LXAduioPlayer.m
//  LXAudioUnit_AAC
//
//  Created by admin on 2019/9/11.
//  Copyright © 2019 admin. All rights reserved.
//

#import "LXAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

static const UInt32 kInputBus = 1;
static const UInt32 kOutputBus = 0;

@interface LXAudioPlayer () {
    AudioUnit ioUnit;
    AudioFileID audioFile;
    AudioConverterRef converterRef;
    SInt64 currPacket;
    Byte *readBuffer;
    uint32_t bufferSize;
    AudioBufferList *converterBufferList;
    UInt32 readSize;
    AudioStreamPacketDescription *packetDescription;
}

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSInputStream *inputStream;
@end
@implementation LXAudioPlayer

- (instancetype)initWithURL:(NSURL *)url {
    if (self = [super init]) {
        _url = url;
        currPacket = 0;
    }
    return self;
}

OSStatus pconverterCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription, void * __nullable inUserData) {
    LXAudioPlayer *player = (__bridge LXAudioPlayer *)inUserData;
    UInt32 byteSize = player->bufferSize;
    OSStatus status = AudioFileReadPacketData(player->audioFile, false, &byteSize, player->packetDescription, player->currPacket, ioNumberDataPackets, player->readBuffer);
    if (outDataPacketDescription) {
        *outDataPacketDescription = player->packetDescription;
    }
    if (status == noErr && ioNumberDataPackets > 0) {
        ioData->mBuffers[0].mDataByteSize = byteSize;
        ioData->mBuffers[0].mData = player->readBuffer;
        player->currPacket += *ioNumberDataPackets;
    }
    return noErr;
}

OSStatus playCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList * __nullable ioData) {
    LXAudioPlayer *player = (__bridge LXAudioPlayer *)inRefCon;
    OSStatus status = AudioConverterFillComplexBuffer(player->converterRef, pconverterCallback, inRefCon, &inNumberFrames, player->converterBufferList, NULL);
    if (status != noErr) {
        NSLog(@"converter format failure");
        return status;
    }
    UInt32 dataSize = player->converterBufferList->mBuffers[0].mDataByteSize;
    memcpy(ioData->mBuffers[0].mData, player->converterBufferList->mBuffers[0].mData, dataSize);
    ioData->mBuffers[0].mDataByteSize = dataSize;
    player->converterBufferList->mBuffers[0].mDataByteSize = player->bufferSize;
    if (dataSize <= 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"play end");
            [player stop];
        });
    }
    return status;
}

- (void)play {
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:true error:nil];
    
    AudioComponentDescription componentDes = {0};
    componentDes.componentType = kAudioUnitType_Output;
    componentDes.componentSubType = kAudioUnitSubType_RemoteIO;
    componentDes.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent component = AudioComponentFindNext(NULL, &componentDes);
    OSStatus status = AudioComponentInstanceNew(component, &ioUnit);
    
    status = AudioFileOpenURL((__bridge CFURLRef)_url, kAudioFileReadPermission, kAudioFileCAFType, &audioFile);
    if (status != noErr) {
        NSLog(@"open file error");
        return;
    }
    AudioStreamBasicDescription dataformat = {0};
    UInt32 size = sizeof(dataformat);
    AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &dataformat, &size);
    dataformat.mSampleRate = 44100.0;
    dataformat.mFormatID = kAudioFormatLinearPCM;
    dataformat.mChannelsPerFrame = 1;
    AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &dataformat, size);
    
    AudioStreamBasicDescription fileFormat = {0};
    size = sizeof(fileFormat);
    status = AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &size, &fileFormat);
    
    int bufferNum = dataformat.mChannelsPerFrame;
    bufferSize = 1024 * bufferNum * 10;
    readBuffer = malloc(bufferSize);
    memset(readBuffer, 0, bufferSize);
    converterBufferList = malloc(sizeof(AudioBufferList) + (bufferNum - 1) * sizeof(AudioBuffer));
    converterBufferList->mNumberBuffers = bufferNum;
    uint32_t sizePerPacket = fileFormat.mFramesPerPacket;
    if (sizePerPacket == 0) {
        UInt32 packetSize = sizeof(sizePerPacket);
        status = AudioFileGetProperty(audioFile, kAudioFilePropertyMaximumPacketSize, &packetSize, &sizePerPacket);
    }
    packetDescription = malloc(sizeof(AudioStreamPacketDescription) * (bufferSize / sizePerPacket + 1));
    
    for (int i = 0; i < bufferNum; i++) {
        converterBufferList->mBuffers[i].mNumberChannels = 1;
        converterBufferList->mBuffers[i].mDataByteSize = bufferSize ;
        converterBufferList->mBuffers[i].mData = malloc(bufferSize);
    }
    
    status = AudioConverterNew(&fileFormat, &dataformat, &converterRef);
    if (status != noErr) {
        NSLog(@"new converter error");
        return;
    }
    
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kOutputBus, &dataformat,  size);
    UInt32 flag = 1;
    AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kOutputBus, &flag, sizeof(flag));
    AURenderCallbackStruct callStruct;
    callStruct.inputProc = playCallback;
    callStruct.inputProcRefCon = (__bridge void*)self;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, kOutputBus, &callStruct, sizeof(callStruct));
    
    status = AudioUnitInitialize(ioUnit);
    status = AudioOutputUnitStart(ioUnit);
}

- (void)stop {
    NSLog(@"play end");
    AudioOutputUnitStop(ioUnit);
    AudioFileClose(audioFile);
    free(readBuffer);
    free(packetDescription);
    currPacket = 0;
}
@end
