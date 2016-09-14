//
//  JWOpenGLView.h
//  JWDecode - H.264
//
//  Created by 黄进文 on 16/9/5.
//  Copyright © 2016年 evenCoder. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

@interface JWOpenGLView : UIView

/**
 *  创建GL
 */
- (void)setupGL;

- (void)displayPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end
