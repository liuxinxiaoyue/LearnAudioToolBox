//
//  LXAudioRecorder.m
//  LXAudioUnit_AAC
//
//  Created by admin on 2019/9/11.
//  Copyright © 2019 admin. All rights reserved.
//

#import "LXAudioRecorder.h"
#import <AVFoundation/AVFoundation.h>

//static UInt32 kOutputBus = 0;
static UInt32 kInputBus = 1;
static UInt32 kBufferSize = 1024 * 10;

@interface LXAudioRecorder () {
    AudioUnit ioUnit;
    AudioConverterRef converterUnit;
    AudioFileID audioFile;
    AudioBufferList *bufferList;
    NSFileHandle *fileHandle;
    UInt32 channel;
    AudioBufferList *converterBufferList;
}

@property (nonatomic, strong) NSURL *url;
@end
@implementation LXAudioRecorder

- (instancetype)initWithURL:(NSURL *)fileURL {
    if (self = [super init]) {
        _url = fileURL;
        if ([[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
            [[NSFileManager defaultManager] removeItemAtURL:fileURL error:nil];
        }
        [[NSFileManager defaultManager] createFileAtPath:fileURL.path contents:nil attributes:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:fileURL.path];
    }
    return self;
}

OSStatus rconverterCallback(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription, void * __nullable inUserData) {
    LXAudioRecorder *recoder = (__bridge LXAudioRecorder *)inUserData;
    AudioBufferList *originBuffer = recoder->bufferList;
    ioData->mNumberBuffers = originBuffer->mNumberBuffers;
    NSUInteger channel = ioData->mNumberBuffers;
    for (int i = 0; i < channel; i++) {
        ioData->mBuffers[i].mNumberChannels = originBuffer->mBuffers[i].mNumberChannels;
        ioData->mBuffers[i].mDataByteSize = originBuffer->mBuffers[i].mDataByteSize;
        ioData->mBuffers[i].mData = originBuffer->mBuffers[i].mData;
    }
    return noErr;
}

OSStatus recordCallback(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList * __nullable ioData) {
    LXAudioRecorder *recorder = (__bridge LXAudioRecorder *)inRefCon;
    OSStatus status = AudioUnitRender(recorder->ioUnit, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, recorder->bufferList);
    if (status != noErr) {
        return status;
    }
    AudioBufferList *convertBufferList = recorder->converterBufferList;
    UInt32 channel = convertBufferList->mNumberBuffers;
    for (int i = 0; i < channel; i++) {
        convertBufferList->mBuffers[i].mDataByteSize = kBufferSize;
        memset(convertBufferList->mBuffers[i].mData, 0, kBufferSize);
    }
    
    UInt32 outPutDataPacketSize = 1;
    status = AudioConverterFillComplexBuffer(recorder->converterUnit, rconverterCallback, inRefCon, &outPutDataPacketSize, convertBufferList, NULL);
    if (status != noErr) {
        NSLog(@"converter format failure");
        return status;
    }
    for (int i = 0; i < convertBufferList->mNumberBuffers; i++) {
        NSData *data = [NSData dataWithBytes:convertBufferList->mBuffers[i].mData length:convertBufferList->mBuffers[i].mDataByteSize];
        NSData *adtsHead = [recorder adtsDataForPacketLength:data.length];
        NSMutableData *frameData = [NSMutableData dataWithData:adtsHead];
        [frameData appendData:data];
        [recorder->fileHandle writeData:frameData];
    }
    return noErr;
}

- (void)record {
    
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];
    [[AVAudioSession sharedInstance] setActive:true error:nil];
    
    AudioComponentDescription componentDesc = {0};
    componentDesc.componentType = kAudioUnitType_Output;
    componentDesc.componentSubType = kAudioUnitSubType_RemoteIO;
    componentDesc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent component = AudioComponentFindNext(NULL, &componentDesc);
    OSStatus status = AudioComponentInstanceNew(component, &ioUnit);
    if (status != noErr) {
        NSLog(@"create io unit failure");
    }
    
    AudioStreamBasicDescription inDataformat = {0};
    UInt32 size = sizeof(AudioStreamBasicDescription);
    status = AudioUnitGetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, kInputBus, &inDataformat, &size);
    
    inDataformat.mSampleRate = 44100.0;
    inDataformat.mChannelsPerFrame = 1;
    status = AudioUnitSetProperty(ioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, kInputBus, &inDataformat, size);
    UInt32 flag = 1;
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, kInputBus, &flag, sizeof(flag));
    
    AURenderCallbackStruct callback;
    callback.inputProc = recordCallback;
    callback.inputProcRefCon = (__bridge void*)self;
    status = AudioUnitSetProperty(ioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Output, kInputBus, &callback, sizeof(callback));
    
    AudioStreamBasicDescription outDataformat = {0};
    outDataformat.mFormatID = kAudioFormatMPEG4AAC;
    outDataformat.mSampleRate = 44100.0;
    size = sizeof(outDataformat);
    status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, &outDataformat);

    status = AudioConverterNew(&inDataformat, &outDataformat, &converterUnit);
    UInt32 outputBitRate = 64000;
    UInt32 propSize = sizeof(outputBitRate);

    if (outDataformat.mSampleRate >= 44100) {
        outputBitRate = 192000;
    } else if (outDataformat.mSampleRate < 22000) {
        outputBitRate = 32000;
    }
    status = AudioConverterSetProperty(converterUnit, kAudioConverterEncodeBitRate, propSize, &outputBitRate);
    
    channel = outDataformat.mChannelsPerFrame != 0? outDataformat.mChannelsPerFrame: 1;
    UInt32 channel = inDataformat.mChannelsPerFrame;
    bufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (channel - 1));
    bufferList->mNumberBuffers = channel;
    for (int i = 0; i < channel; i++) {
        AudioBuffer buffer = {0};
        buffer.mNumberChannels = 1;
        buffer.mDataByteSize = kBufferSize;
        buffer.mData = malloc(kBufferSize);
        bufferList->mBuffers[i] = buffer;
    }

    converterBufferList = (AudioBufferList *)malloc(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (channel - 1));
    converterBufferList->mNumberBuffers = channel;
    for (int i = 0; i < channel; i++) {
        AudioBuffer buffer = {0};
        buffer.mNumberChannels = 1;
        buffer.mDataByteSize = kBufferSize;
        buffer.mData = malloc(kBufferSize);
        converterBufferList->mBuffers[i] = buffer;
    }
    status = AudioUnitInitialize(ioUnit);
    status = AudioOutputUnitStart(ioUnit);
}

- (void)stop {
    AudioOutputUnitStop(ioUnit);
    [fileHandle closeFile];
    AudioConverterDispose(converterUnit);
    free(converterBufferList);
    free(bufferList);
}

- (NSData*)adtsDataForPacketLength:(NSUInteger)packetLength {
    int adtsLength = 7;
    char *packet = malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 4;  //44.1KHz
    int chanCfg = 1;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}
@end
