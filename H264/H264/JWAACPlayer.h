//
//  JWAACPlayer.h
//  H264
//
//  Created by 黄进文 on 16/9/17.
//  Copyright © 2016年 evenCoder. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface JWAACPlayer : NSObject

- (instancetype)initWithUrl:(NSURL *)url;

- (void)play;

- (double)getCurrentTime;

@end
