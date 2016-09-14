//
//  JWViewController.m
//  H264
//
//  Created by 黄进文 on 16/9/14.
//  Copyright © 2016年 evenCoder. All rights reserved.
//

#import "JWEncodeViewController.h"
#import "JWCaptureView.h"

@implementation JWEncodeViewController

- (void)viewDidLoad {
    
    [super viewDidLoad];
    JWCaptureView *captureView = [[JWCaptureView alloc] initWithCapturePosition:AVCaptureDevicePositionBack];
    captureView.frame = CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, [[UIScreen mainScreen] bounds].size.height);
    [self.view addSubview:captureView];
}

/**
 *  隐藏状态栏
 */
- (BOOL)prefersStatusBarHidden {
    
    return YES;
}

@end
