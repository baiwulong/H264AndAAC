//
//  JWAACPlayer.m
//  H264
//
//  Created by 黄进文 on 16/9/17.
//  Copyright © 2016年 evenCoder. All rights reserved.
//
/**
 1,读取MP3文件
 
 2,解析采样率、码率、时长等信息，分离MP3中的音频帧
 
 4,对分离出来的音频帧解码得到PCM数据
 
 5,对PCM数据进行音效处理（均衡器、混响器等，非必须）
 
 6,把PCM数据解码成音频信号
 
 7,音频信号交给硬件播放
 
 8,1-6步直到播放完成
 */

#import "JWAACPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

const uint32_t CONST_BUFFER_COUNT = 3;

const uint32_t CONST_BUFFER_SIZE = 0x10000;

@interface JWAACPlayer() {
    
    NSURL *_AACURL;
    // 文件操作 定义一个不透明的数据类型，代表一个audiofile的对象
    AudioFileID audioFileID;
    // 音频数据流格式的描述.Callback Method 回调函数，系统规定好了回调函数的参数，以及调用的地方，你只需要保证参数的格式正确，向函数里添加代码即可，函数的方法名称可以随便写，没有强制的规定。
    AudioStreamBasicDescription audioStreamBaseDescrition;

    AudioStreamPacketDescription *audioStreamPacketDescription; //数据包的格式不同时会不同
    
    // 定义的一个不透明的数据类型，专门用来代表一个audio queue
    // 使用一个缓冲队列来存储data，用来播放或录音。播放或录音的时候，数据以流的形式操作，可以边获取数据变播放，或者边录音，边存储。
    AudioQueueRef audioQueue; //音频队列对象指针
    
    // 是AudioQueueBuffer的别名，表明该参数为一个AudioQueueBuffer对象
    AudioQueueBufferRef audioQueueBuffers[CONST_BUFFER_COUNT];  //音频流缓冲区对象
    
    SInt64 readedPacket; // 参数类型
    
    u_int32_t packetNums;
}

@end

@implementation JWAACPlayer

- (instancetype)initWithUrl:(NSURL *)url {
    if (self = [super init]) {
        _AACURL = url;
        [self customAudioConfig:_AACURL];
    }
    return self;
}

- (void)play {
    // Sets a playback audio queue parameter value.
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    // Begins playing or recording audio.
    AudioQueueStart(audioQueue, NULL);
}

- (double)getCurrentTime {
    
    Float64 timeInterval = 0.0;
    if (audioQueue) {
        
        AudioQueueTimelineRef timeLine;
        AudioTimeStamp timeStamp;
        // Creates a timeline object for an audio queue.
        OSStatus status = AudioQueueCreateTimeline(audioQueue, &timeLine);
        if (status == noErr) {
            
            // Gets the current audio queue time.
            AudioQueueGetCurrentTime(audioQueue, timeLine, &timeStamp, NULL);
            // The number of sample frames per second of the data in the stream.
            timeInterval = timeStamp.mSampleTime * 1000000 / audioStreamBaseDescrition.mSampleRate;
        }
    }
    return timeInterval;
}

- (void)customAudioConfig:(NSURL *)url {
    // 打开音频文件
    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)url, kAudioFileReadPermission, 0, &audioFileID);
    if (status != noErr) {
        return;
    }

    //从音频文件中读取属性值，获取audio的format(就是录制的时候配置的参数)
    uint32_t size = sizeof(audioStreamBaseDescrition);
    status = AudioFileGetProperty(audioFileID, kAudioFilePropertyDataFormat, &size, &audioStreamBaseDescrition);
    NSAssert(status == noErr, @"error");
    
    // Creates a new playback audio queue object.
    status = AudioQueueNewOutput(&audioStreamBaseDescrition,
                                 bufferReady,
                                 (__bridge void * _Nullable)(self),
                                 NULL,
                                 NULL,
                                 0,
                                 &audioQueue);
    NSAssert(status == noErr, @"error");
    
    //    在整个Core Audio中可能会用到三种不同的packets：
    //    CBR (constant bit rate) formats：例如 linear PCM and IMA/ADPCM，所有的packet使用相同的大小。
    //    VBR (variable bit rate) formats：例如 AAC，Apple Lossless，MP3，所有的packets拥有相同的frames，但是每个sample中的bits数目不同。
    //    VFR (variable frame rate) formats：packets拥有数目不同的的frames。
    bool isFormatVBR = (audioStreamBaseDescrition.mBytesPerPacket == 0 || audioStreamBaseDescrition.mFramesPerPacket == 0);
    if (isFormatVBR) {
        uint32_t maxPacketSize;
        size = sizeof(maxPacketSize);
        // The theoretical maximum packet size in the file.
        AudioFileGetProperty(audioFileID, kAudioFilePropertyPacketSizeUpperBound, &size, &maxPacketSize);
        if (maxPacketSize > CONST_BUFFER_SIZE) {
            maxPacketSize = CONST_BUFFER_SIZE;
        }
        packetNums = CONST_BUFFER_SIZE / maxPacketSize;
        audioStreamPacketDescription = malloc(sizeof(AudioStreamPacketDescription) * packetNums);
    }
    else {
        // linearPCM
        packetNums = CONST_BUFFER_SIZE / audioStreamBaseDescrition.mBytesPerPacket;
        audioStreamPacketDescription = nil;
    }
    
    char cookies[100];
    memset(cookies, 0, sizeof(cookies));
    // 这里的100 有问题
    // Some file types require that a magic cookie be provided before packets can be written to an audio file.
    AudioFileGetProperty(audioFileID, kAudioFilePropertyMagicCookieData, &size, cookies);
    if (size > 0) {
        // Sets an audio queue property value.
        AudioQueueSetProperty(audioQueue, kAudioQueueProperty_MagicCookie, cookies, size);
    }
    readedPacket = 0;
    for (int i = 0; i < CONST_BUFFER_COUNT; ++i) {
        // Asks an audio queue object to allocate an audio queue buffer.
        AudioQueueAllocateBuffer(audioQueue, CONST_BUFFER_SIZE, &audioQueueBuffers[i]);
        if ([self fillWithBuffer:audioQueueBuffers[i]]) {
            // full
            break;
        }
        NSLog(@"buffer%d full", i);
    }
    
}

void bufferReady(void *inUserData, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    
    NSLog(@"refresh buffer");
    JWAACPlayer *player = (__bridge JWAACPlayer *)inUserData;
    if (!player) {
        NSLog(@"player nil");
        return;
    }
    if ([player fillWithBuffer:buffer]) {
        
        NSLog(@"player end");
    }
}

- (BOOL)fillWithBuffer:(AudioQueueBufferRef)buffer {
    
    BOOL full = NO;
    uint32_t bytes = 0, packets = (uint32_t)packetNums;
    // Reads packets of audio data from an audio file.
    OSStatus status = AudioFileReadPackets(audioFileID, NO, &bytes, audioStreamPacketDescription, readedPacket, &packets, buffer->mAudioData);
    // OSStatus status = AudioFileReadPacketData(audioFileID, NO, &bytes, audioStreamPacketDescription, readedPacket, &packets, buffer->mAudioData);
    
    NSAssert(status == noErr, ([NSString stringWithFormat:@"error status %d", status]));
    if (packets > 0) {
        
        buffer->mAudioDataByteSize = bytes;
        AudioQueueEnqueueBuffer(audioQueue, buffer, packets, audioStreamPacketDescription);
        readedPacket += packets;
    }
    else {
        
        AudioQueueStop(audioQueue, NO);
        full = YES;
    }
    return full;
}

@end



























