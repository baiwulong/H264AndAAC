//
//  JWAACEncode.m
//  JWEncode - H.264
//
//  Created by 黄进文 on 16/9/7.
//  Copyright © 2016年 evenCoder. All rights reserved.
//

#import "JWAACEncode.h"

@interface JWAACEncode()

@property (nonatomic) AudioConverterRef jAudioConverter;
@property (nonatomic) uint8_t *jAACBuffer;
@property (nonatomic) uint32_t jAACBufferSize;
@property (nonatomic) char *jPCMBuffer;
@property (nonatomic) size_t jPCMBufferSize;

@end

@implementation JWAACEncode

/**
 *  初始化数据
 */
- (instancetype)init {
    if (self = [super init]) {
        _jEncoderQueue = dispatch_queue_create("AAC Encoder Queue", DISPATCH_QUEUE_SERIAL);
        _jCallBackQueue = dispatch_queue_create("AAC Encoder Callback Queue", DISPATCH_QUEUE_SERIAL);
        _jAudioConverter = NULL;
        _jPCMBufferSize = 0;
        _jPCMBuffer = NULL;
        _jAACBufferSize = 1024;
        _jAACBuffer = malloc(_jAACBufferSize * sizeof(uint8_t));
        // void *memset(void *s, int ch, size_t n);
        // 函数解释：将s中当前位置后面的n个字节 （typedef unsigned int size_t ）用 ch 替换并返回 s 。
        memset(_jAACBuffer, 0, _jAACBufferSize);
    }
    return self;
}


// MARK: - 编码


- (void)encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer completianBlock:(void (^)(NSData *, NSError *))completionBlock {
    CFRetain(sampleBuffer);
    dispatch_async(_jEncoderQueue, ^{
        if (!_jAudioConverter) {
            // 初始化音频转换器
            [self setupAudioConverter:sampleBuffer];
        }
        // 调用者不拥有返回的dataBuffer，如果调用者需要维护对它的引用，则必须显式保留它
        CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        CFRetain(blockBuffer);
        
        // PCM: 获取pcmBuffer数据
        OSStatus status = CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &_jPCMBufferSize, &_jPCMBuffer);
        NSError *error = nil;
        if (status != kCMBlockBufferNoErr) {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        NSLog(@"PCM Buffer size %zu", _jPCMBufferSize);
        
        // AAC: 把AACBuffer指针后面的size内存设置为0值
        memset(_jAACBuffer, 0, _jAACBufferSize);
        
        // 输出音频缓冲list
        AudioBufferList outAudioBufferList = {0};
        outAudioBufferList.mNumberBuffers = 1;
        outAudioBufferList.mBuffers[0].mNumberChannels = 1;
        outAudioBufferList.mBuffers[0].mDataByteSize = _jAACBufferSize;
        outAudioBufferList.mBuffers[0].mData = _jAACBuffer;
        
        // 填充buffer数据
        AudioStreamPacketDescription *outPacketDesc = NULL;
        uint32_t ioOutputDataPacketSize = 1;
        status = AudioConverterFillComplexBuffer(_jAudioConverter,
                                                 inInputDataProc,           // 提供输入input数据
                                                 (__bridge void *)(self),   // 传递到回调函数中的使用者
                                                 &ioOutputDataPacketSize,
                                                 &outAudioBufferList,       // 输出buffer数据
                                                 outPacketDesc);
        NSData *data = nil;
        if (status == 0) {
            AudioBuffer aacBuffer = outAudioBufferList.mBuffers[0];
            NSData *rawAAC = [NSData dataWithBytes:aacBuffer.mData length:aacBuffer.mDataByteSize];
            NSData *adtsHeader = [self getADTSDataWithPacketLength:rawAAC.length];
            NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
            [fullData appendData:rawAAC];
            data = fullData;
        } else {
            error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
        }
        if (completionBlock) {
            dispatch_async(_jCallBackQueue, ^{
                completionBlock(data, error);
            });
        }
        CFRelease(sampleBuffer);
        CFRelease(blockBuffer);
    });
}

/**
 *  设置编码参数
 *
 *  @param sampleBuffer 音频
 */
// 在AAC编码的场景下，源格式就是采集到的PCM数据，目的格式就是AAC
- (void)setupAudioConverter:(CMSampleBufferRef)sampleBuffer {
    // buffer的音频格式描述 -》输入音频流描述
    CMAudioFormatDescriptionRef fmtDescRef = (CMAudioFormatDescriptionRef)CMSampleBufferGetFormatDescription(sampleBuffer);
    AudioStreamBasicDescription inAudioStreamDesc = *CMAudioFormatDescriptionGetStreamBasicDescription(fmtDescRef);
    inAudioStreamDesc.mFormatID = kAudioFormatLinearPCM; //PCM采样
    
    /* 输出流格式描述 */
    /**
     音频采样率：是指录音设备在一秒钟内对声音信号的采样次数，采样频率越高声音的还原就越真实越自然。
     在当今的主流采集卡上，采样频率一般共分为22.05KHz、44.1KHz、48KHz三个等级，
     22.05KHz只能达到FM广播的声音品质，44.1KHz则是理论上的CD音质界限，48KHz则更加精确一些
     */
    // inAudioStreamDesc.mSampleRate = 44100; //采样率
    // inAudioStreamDesc.mBitsPerChannel = 16;
    // inAudioStreamDesc.mFramesPerPacket = 1; //每个数据包多少帧
    // inAudioStreamDesc.mBytesPerFrame = 2;
    // inAudioStreamDesc.mBytesPerPacket = inAudioStreamDesc.mBytesPerFrame * inAudioStreamDesc.mFramesPerPacket;
    // inAudioStreamDesc.mReserved = 0;
    
    // 初始化输出流的结构体描述为0. 很重要。
    AudioStreamBasicDescription outAudioStreamDesc = {0};
    // 音频流，在正常播放情况下的帧率。如果是压缩的格式，这个属性表示解压缩后的帧率。帧率不能为0。
    outAudioStreamDesc.mSampleRate = inAudioStreamDesc.mSampleRate;
    // 设置AAC编码格式
    outAudioStreamDesc.mFormatID = kAudioFormatMPEG4AAC;
    outAudioStreamDesc.mFormatFlags = kMPEG4Object_AAC_LC;
    // 每个packet的帧数。如果是未压缩的音频数据，值是1。动态帧率格式，这个值是一个较大的固定数字，比如说AAC的1024。如果是动态大小帧数（比如Ogg格式）设置为0。
    outAudioStreamDesc.mFramesPerPacket = 1024;
    // 每一个packet的音频数据大小。如果的动态大小设置为0。动态大小的格式需要用AudioStreamPacketDescription来确定每个packet的大小。
    outAudioStreamDesc.mBytesPerPacket = 0;
    // 声道数 1单声道，2立体声
    outAudioStreamDesc.mChannelsPerFrame = 1;
    //  每帧的大小。每一帧的起始点到下一帧的起始点。如果是压缩格式，设置为0 。
    outAudioStreamDesc.mBytesPerFrame = 0;
    // 压缩格式设置为0
    outAudioStreamDesc.mBitsPerChannel = 0;
    // 8字节对齐，填0.
    outAudioStreamDesc.mReserved = 0;
    
    AudioClassDescription *description = [self getAudioClassDescriptionWithType:kAudioFormatMPEG4AAC
                                                               withManufacturer:kAppleSoftwareAudioCodecManufacturer];
    // 根据输入和输出音频格式，以及指定的音频转换器类别，创建一个音频转换器对象。
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamDesc,
                                                &outAudioStreamDesc,
                                                1,
                                                description,
                                                &_jAudioConverter);
    if (status != 0) {
        NSLog(@"create converter success: %d", (int)status);
    } else {
        NSLog(@"create converter error: %d", (int)status);
    }
}

- (AudioClassDescription *)getAudioClassDescriptionWithType:(UInt32)type withManufacturer:(UInt32)manufacturer {
    static AudioClassDescription desc;
    UInt32 encoderSpecifier = type;
    UInt32 size;
    OSStatus status = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (status) {
        NSLog(@"error getting audio format propery info: %d", (int)(status));
        return nil;
    }
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    OSStatus statusDesc = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, descriptions);
    if (statusDesc) {
        NSLog(@"error getting audio format propery: %d", (int)(statusDesc));
        return nil;
    }
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) && (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    return nil;
}



// MARK: - callback

static OSStatus inInputDataProc(AudioConverterRef inAudioConverter,
                                UInt32 *ioNumberDataPackets,
                                AudioBufferList *ioData,
                                AudioStreamPacketDescription **outDataPacketDescription,
                                void *inUserData)
{
    JWAACEncode *encoder = (__bridge JWAACEncode *)(inUserData);
    size_t copySameples = [encoder copyPCMSamplesIntoBuffer:ioData];
    
    uint32_t requestedPackets = *ioNumberDataPackets;
    if (copySameples < requestedPackets) {
        *ioNumberDataPackets = 0; // 表示动态大小
        return -1;
    }
    *ioNumberDataPackets = 1;
    return noErr;
}

/**
 *  填充PCM到缓冲区
 */
- (size_t)copyPCMSamplesIntoBuffer:(AudioBufferList *)ioData {
    size_t orignalBufferSize = _jPCMBufferSize;
    if (!orignalBufferSize) {
        return 0;
    }
    ioData->mBuffers[0].mData = _jPCMBuffer;
    ioData->mBuffers[0].mDataByteSize = (uint32_t)_jPCMBufferSize;
    _jPCMBuffer = NULL;
    _jPCMBufferSize = 0;
    return orignalBufferSize;
    
}

// MARK: -

/**
 *  Add ADTS header at the beginning of each and every AAC packet.
 *  This is needed as MediaCodec encoder generates a packet of raw
 *  AAC data.
 *
 *  Note the packetLen must count in the ADTS header itself.
 *  See: http://wiki.multimedia.cx/index.php?title=ADTS
 *  Also: http://wiki.multimedia.cx/index.php?title=MPEG-4_Audio#Channel_Configurations
 **/
- (NSData *)getADTSDataWithPacketLength:(NSInteger)packetLength {
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

- (void)dealloc {
    
    AudioConverterDispose(_jAudioConverter);
    free(_jAACBuffer);
}

@end







































