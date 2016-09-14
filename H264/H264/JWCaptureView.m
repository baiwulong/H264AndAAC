//
//  JWCaptureView.m
//  H264
//
//  Created by 黄进文 on 16/9/14.
//  Copyright © 2016年 evenCoder. All rights reserved.
//

#import "JWCaptureView.h"
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <AudioToolbox/AudioToolbox.h>

#define SCREENWIDTH  [UIScreen mainScreen].bounds.size.width
#define SCREENHEIGH  [UIScreen mainScreen].bounds.size.height
#define buttonWH 50

@interface JWCaptureView() <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate> {
    
    AVCaptureDevicePosition _position;
    int frameID;
    dispatch_queue_t jCaptureQueue;
    dispatch_queue_t jEncodeQueue;
    dispatch_queue_t jAudioQueue;
    VTCompressionSessionRef jEncodingSession;
    CMFormatDescriptionRef  jFormat;
    NSFileHandle *jFileHandle;
    NSFileHandle *jAudioHandle;
    
    AVCaptureDevice *jCameraDeviceBack; // 后置
    AVCaptureDevice *jCameraDeviceFont; // 前置
    AVCaptureDeviceInput *_currentVideoDeviceInput;  // 视频输入源
    BOOL cameraDeviceIsFontOrBack;
}

/**
 *  负责输入和输出设备之间的数据传递
 */
@property (nonatomic, strong) AVCaptureSession *jCaptureSession;

/**
 *  负责AVCaptureDevice获得输入数据
 */
// @property (nonatomic, strong) AVCaptureDeviceInput *jCaptureDeviceInput;

/**
 *  负责AVCaptureDevice获得输出数据
 */
@property (nonatomic, strong) AVCaptureVideoDataOutput *jCaptureDeviceOutput;

/**
 *  设备信息
 */
@property (nonatomic, strong) AVCaptureDevice *jCaptureDevice;

/**
 *  设备显示视频
 */
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *jPreviewLayer;

/**
 *  输出流
 */
@property (nonatomic, strong) AVCaptureConnection *jVideoConnection;

/**
 *  中心点按钮
 */
@property (nonatomic, strong) UIButton *centerButton;

@property (nonatomic, strong) UIView *backView;

/**
 *  记录开始缩放比例
 */
@property (nonatomic, assign) CGFloat beginGestureScale;

/**
 *  记录最后缩放比例
 */
@property (nonatomic, assign) CGFloat endGestureScale;

/**
 *  音频
 */
@property (nonatomic, strong) AVCaptureConnection  *jAudioConnection;

// @property (nonatomic, strong) JWAACEncode *jAACEcode;


@end

@implementation JWCaptureView

- (AVCaptureSession *)jCaptureSession {
    
    if (!_jCaptureSession) {
        
        // 创建捕获会话,必须要强引用，否则会被释放
        self.jCaptureSession = [[AVCaptureSession alloc] init];
    }
    return _jCaptureSession;
}

- (instancetype)initWithCapturePosition:(AVCaptureDevicePosition)position {
    
    if (self = [super init]) {
        
        // 标记摄像头前后
        _position = position;
        
        [self initCapture];
        // 路径
        NSLog(@"沙盒路径: %@", NSTemporaryDirectory());
    }
    return self;
}

- (void)initCapture {
    
    // 创建中心按钮 打开开始录视频
    [self setupCenterButton];
    // 切换摄像头
    [self setupSwipButton];
}

#pragma mark - centerButton 打开摄像头
- (void)setupCenterButton {
    
    self.centerButton = [[UIButton alloc] initWithFrame:CGRectMake((SCREENWIDTH - buttonWH) * 0.5, SCREENHEIGH - 2.5 * buttonWH, buttonWH, buttonWH)];
    self.centerButton.layer.cornerRadius = buttonWH * 0.5;
    self.centerButton.layer.masksToBounds = YES;
    [self.centerButton setImage:[UIImage imageNamed:@"logo_3745aaf"] forState:UIControlStateNormal];
    [self.centerButton addTarget:self action:@selector(centerBtnClick:) forControlEvents:UIControlEventTouchUpInside];
    // 加阴影
    self.centerButton.layer.shadowColor = [UIColor blackColor].CGColor; // shadowColor阴影颜色
    self.centerButton.layer.shadowOffset = CGSizeMake(0, 0); // shadowOffset阴影偏移, 这个跟shadowRadius配合使用
    self.centerButton.layer.shadowOpacity = 0.5; // //阴影透明度，默认0
    self.centerButton.layer.shadowRadius = 1; // //阴影半径，默认3
    [self addSubview:self.centerButton];
}

// 切换摄像头时暂时还不能重新编码
- (void)centerBtnClick:(UIButton *)sender {
    
    if (!self.jCaptureSession || !self.jCaptureSession.running) {
        
        //[self startAudioCapture];
        [self startVideoCapture];
    }
    else {
        
        [self stopCapture];
    }
}

#pragma mark - 切换摄像头
/**
 *  切换摄像头
 */
- (void)setupSwipButton {
    
    // 返回
    UIButton *backBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    backBtn.frame = CGRectMake(SCREENWIDTH - 35 - 20, 64 * 0.5, 35, 35);
    [backBtn setImage:[UIImage imageNamed:@"close_preview"] forState:UIControlStateNormal];
    [backBtn addTarget:self action:@selector(swipButtonClick:) forControlEvents:UIControlEventTouchUpInside];
    // 加阴影
    backBtn.layer.shadowColor = [UIColor blackColor].CGColor; // shadowColor阴影颜色
    backBtn.layer.shadowOffset = CGSizeMake(0, 0); // shadowOffset阴影偏移, 这个跟shadowRadius配合使用
    backBtn.layer.shadowOpacity = 0.5; // //阴影透明度，默认0
    backBtn.layer.shadowRadius = 1; // //阴影半径，默认3
    [self addSubview:backBtn];
}

- (void)swipButtonClick:(UIButton *)sender {
    
    NSLog(@"切换摄像头");
    // 获取当前设备方向
    AVCaptureDevicePosition currentPosition = _currentVideoDeviceInput.device.position;
    
    // 获取需要改变的方向
    AVCaptureDevicePosition changePosition = (currentPosition == AVCaptureDevicePositionFront) ? AVCaptureDevicePositionBack : AVCaptureDevicePositionFront;
    
    // 获取改变的摄像头设备
    AVCaptureDevice *changeDevice = [self getCameraDevice:changePosition];
    
    // 获取改变的摄像头输入设备
    AVCaptureDeviceInput *changeDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:changeDevice error:nil];
    
    // 移除之前摄像头输入设备
    [self.jCaptureSession removeInput:_currentVideoDeviceInput];
    
    // 添加新的摄像头输入设备
    [self.jCaptureSession addInput:changeDeviceInput];
    
    // 记录当前摄像头输入设备
    _currentVideoDeviceInput = changeDeviceInput;
}

#pragma mark - 获取输入源
/**
 *  获取输入源
 */
- (AVCaptureDevice *)getCameraDevice:(AVCaptureDevicePosition)position {
    
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]; // 获取设备
    for (AVCaptureDevice *device in devices) {
        
        if (device.position == position) {
            
            return device;
        }
    }
    return nil;
}

#pragma mark - 开始视频
- (void)startVideoCapture {
    
    
    jCaptureQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    jEncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    // 设置录像分辨率
    self.jCaptureSession.sessionPreset = AVCaptureSessionPreset1280x720; // session的采集解析度
    
    // 获取摄像头设备，默认前置
    AVCaptureDevice *videoDevice = [self getCameraDevice:_position];
    
    // 创建对应视频设备输入对象
    AVCaptureDeviceInput *videoDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:nil];
    _currentVideoDeviceInput = videoDeviceInput;
    // 添加到会话中
    // 注意“最好要判断是否能添加输入，会话不能添加空的
    // 添加视频
    if ([self.jCaptureSession canAddInput:videoDeviceInput]) {
        
        [self.jCaptureSession addInput:videoDeviceInput];
    }
    /**
     如果队列被阻塞，新的图像帧到达后会被自动丢弃(默认alwaysDiscardsLateVideoFrames = YES)。这允许app处理当前的图像帧，不需要去管理不断增加的内存，因为处理速度跟不上采集的速度，等待处理的图像帧会占用内存，并且不断增大。必须使用同步队列处理图像帧，保证帧的序列是顺序的。
     */
    // 7.获取视频数据输出设备
    self.jCaptureDeviceOutput = [[AVCaptureVideoDataOutput alloc] init];
    [self.jCaptureDeviceOutput setAlwaysDiscardsLateVideoFrames:NO];
    
    [self.jCaptureDeviceOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
    // 设置代理
    [self.jCaptureDeviceOutput setSampleBufferDelegate:self queue:jCaptureQueue];
    
    if ([self.jCaptureSession canAddOutput:self.jCaptureDeviceOutput]) {
        
        [self.jCaptureSession addOutput:self.jCaptureDeviceOutput];
    }
    // 获取视频输入与输出连接，用于分辨音视频数据
    self.jVideoConnection = [self.jCaptureDeviceOutput connectionWithMediaType:AVMediaTypeVideo];  // 输出视频
    [self.jVideoConnection setVideoOrientation:AVCaptureVideoOrientationPortrait];
    
    // 添加视频预览图层
    self.jPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.jCaptureSession];
    // 调整摄像头位置
    self.jPreviewLayer.position = CGPointMake(self.frame.size.width * 0.5, self.frame.size.height * 0.5);
    self.jPreviewLayer.bounds = CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, [[UIScreen mainScreen] bounds].size.height);
    [self.jPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspect]; // 设置预览时的视频缩放方式
    [self.layer insertSublayer:self.jPreviewLayer atIndex:0];

    // 视频编码保存的路径
    NSString *filePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] stringByAppendingPathComponent:@"test.h264"];
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil]; // 移除旧文件
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil]; // 创建新文件
    jFileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];  // 管理写进文件
    
    [self initVideoToolBox]; // 初始化视频编码数据
    [self.jCaptureSession commitConfiguration];
    [self.jCaptureSession startRunning]; // 打开摄像头
}

#pragma mark - 初始化VideoToolBox编码
- (void)initVideoToolBox {
    
    // 初始化jEncodingSession属性
    dispatch_sync(jEncodeQueue, ^{
        
        frameID = 0;
        // VTCompressionSession初始化的时候，一般需要给出width宽，height长，编码器类型kCMVideoCodecType_H264
        int width = (int)self.bounds.size.width;
        int height = (int)self.bounds.size.height;
        // kCMVideoCodecType_H264 编码:h.264
        // didCompressH264 回调函数(回调是视频图像编码成功后调用)
        OSStatus status = VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didCompressH264, (__bridge void *)(self), &jEncodingSession);
        NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        if (status != 0) {
            
            NSLog(@"H264: Unable to create a H264 session");
            return ;
        }
        
        // VTSessionSetProperty接口设置帧率等属性
        // kVTCompressionPropertyKey_ProfileLevel : Specifies the profile and level for the encoded bitstream.
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        
        // 设置关键帧(GOPsize)间隔
        int frameInterval = 10;
        CFNumberRef frameintervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameintervalRef);
        
        // 设置期望帧率
        int fps = 10;
        CFNumberRef fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);
        
        //设置码率，上限，单位是bps
        int bitRate = width * height * 3 * 4 * 8;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);
        
        // 设置码率，均值，单位是byte
        int bitRateLimit = width * height * 3 * 4;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(jEncodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);
        
        // Tell the encoder to start encoding 可以开始编码
        VTCompressionSessionPrepareToEncodeFrames(jEncodingSession);
    });
}

#pragma mark - <AVCaptureVideoDataOutputSampleBufferDelegate>开始编码
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    
    CMTime pts = CMSampleBufferGetDuration(sampleBuffer);
    
    double dPTS = (double)(pts.value) / pts.timescale;
    NSLog(@"DPTS is %f",dPTS);
    
    if (connection == self.jVideoConnection) {
        
        dispatch_sync(jEncodeQueue, ^{
            // 摄像头采集后的图像是未编码的CMSampleBuffer形式，
            [self encode:sampleBuffer];
        });
    }
    else if (connection == self.jAudioConnection) {
        
//        [self.jAACEcode encodeSampleBuffer:sampleBuffer completianBlock:^(NSData *encodedData, NSError *error) {
//            
//            if (encodedData) {
//                NSLog(@"音频");
//                // NSLog(@"Audio data.length (%lu):%@", (unsigned long)encodedData.length,encodedData.description);
//                // 将encodedData写入jAudioHandle
//                [jAudioHandle writeData:encodedData];
//            }
//        }];
    }
}

// 开始编码 CMSampleBuffer：存放编解码前后的视频图像的容器数据结构
- (void)encode:(CMSampleBufferRef)sampleBuffer {
    
    // CVPixelBufferRef 编码前图像数据结构
    // 利用给定的接口函数CMSampleBufferGetImageBuffer从中提取出CVPixelBufferRef
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    // 帧时间, 如果不设置会导致时间轴过长
    CMTime presentationTimeStamp = CMTimeMake(frameID++, 1000);
    VTEncodeInfoFlags flags;
    // 使用硬编码接口VTCompressionSessionEncodeFrame来对该帧进行硬编码
    // 编码成功后，会自动调用session初始化时设置的回调函数
    OSStatus statusCode = VTCompressionSessionEncodeFrame(jEncodingSession, imageBuffer, presentationTimeStamp, kCMTimeInvalid, NULL, NULL, &flags);
    if (statusCode != noErr) {
        
        NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        VTCompressionSessionInvalidate(jEncodingSession);
        CFRelease(jEncodingSession);
        jEncodingSession = NULL;
        return;
    }
    NSLog(@"H264: VTCompressionSessionEncodeFrame Success : %d", (int)statusCode);
}

#pragma mark - 编码完成回调
/**
 *  h.264硬编码完成后回调 VTCompressionOutputCallback
 *  将硬编码成功的CMSampleBuffer转换成H264码流，通过网络传播
 *  解析出参数集SPS和PPS，加上开始码后组装成NALU。提取出视频数据，将长度码转换成开始码，组长成NALU。将NALU发送出去。
 */
void didCompressH264(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    
    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags);
    if (status != 0) {
        return;
    }
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    
    JWCaptureView *encoder = (__bridge JWCaptureView *)outputCallbackRefCon;
    bool keyframe = !CFDictionaryContainsKey( (CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0)), kCMSampleAttachmentKey_NotSync);
    // 判断当前帧是否为关键帧 获取sps & pps 数据
    // 解析出参数集SPS和PPS，加上开始码后组装成NALU。提取出视频数据，将长度码转换成开始码，组长成NALU。将NALU发送出去。
    if (keyframe) {
        
        // CMVideoFormatDescription：图像存储方式，编解码器等格式描述
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        // sps
        size_t sparameterSetSize, sparameterSetCount;
        const uint8_t *sparameterSet;
        OSStatus statusSPS = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0);
        if (statusSPS == noErr) {
            
            // Found sps and now check for pps
            // pps
            size_t pparameterSetSize, pparameterSetCount;
            const uint8_t *pparameterSet;
            OSStatus statusPPS = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0);
            if (statusPPS == noErr) {
                
                // found sps pps
                NSData *sps = [NSData dataWithBytes:sparameterSet length:sparameterSetSize];
                NSData *pps = [NSData dataWithBytes:pparameterSet length:pparameterSetSize];
                if (encoder) {
                    
                    [encoder gotSPS:sps withPPS:pps];
                }
            }
        }
    }
    
    // 编码后的图像，以CMBlockBuffe方式存储
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr) {
        
        size_t bufferOffSet = 0;
        // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        static const int AVCCHeaderLength = 4;
        
        // 循环获取nalu数据
        while (bufferOffSet < totalLength - AVCCHeaderLength) {
            
            uint32_t NALUUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUUnitLength, dataPointer + bufferOffSet, AVCCHeaderLength);
            // 从大端转系统端
            NALUUnitLength = CFSwapInt32BigToHost(NALUUnitLength);
            NSData *data = [[NSData alloc] initWithBytes:(dataPointer + bufferOffSet + AVCCHeaderLength) length:NALUUnitLength];
            [encoder gotEncodedData:data isKeyFrame:keyframe];
            
            // Move to the next NAL unit in the block buffer
            bufferOffSet += AVCCHeaderLength + NALUUnitLength;
        }
    }
}

#pragma mark - 编码完成写入h264文件中
- (void)gotSPS:(NSData *)sps withPPS:(NSData *)pps {
    
    NSLog(@"gotSPSAndPPS %d withPPS %d", (int)[sps length], (int)[pps length]);
    const char bytes[] = "\x00\x00\x00\x01";
    size_t length = (sizeof bytes) - 1;
    NSData *byteHeader = [NSData dataWithBytes:bytes length:length];
    [jFileHandle writeData:byteHeader];
    [jFileHandle writeData:sps];
    [jFileHandle writeData:byteHeader];
    [jFileHandle writeData:pps];
}

- (void)gotEncodedData:(NSData *)data isKeyFrame:(BOOL)isKeyFrame {
    
    NSLog(@"gotEncodedData %d", (int)[data length]);
    if (jFileHandle != NULL) {
        
        const char bytes[]= "\x00\x00\x00\x01";
        size_t lenght = (sizeof bytes) - 1;
        NSData *byteHeader = [NSData dataWithBytes:bytes length:lenght];
        [jFileHandle writeData:byteHeader];
        [jFileHandle writeData:data];
    }
}

#pragma mark - 关闭摄像头
- (void)stopCapture {
    
    [self.jCaptureSession stopRunning];
    [self.jPreviewLayer removeFromSuperlayer];
    [self endVideoToolBox];
    [jFileHandle closeFile];
    jFileHandle = NULL;
}

#pragma mark - 停止编码
- (void)endVideoToolBox {
    
    VTCompressionSessionCompleteFrames(jEncodingSession, kCMTimeInvalid);
    VTCompressionSessionInvalidate(jEncodingSession);
    CFRelease(jEncodingSession);
    jEncodingSession = NULL;
}


@end








































