//
//  ViewController.m
//  LXAudioUnit_AAC
//
//  Created by admin on 2019/9/11.
//  Copyright © 2019 admin. All rights reserved.
//

#import "ViewController.h"
#import "LXAudioRecorder.h"
#import "LXAudioPlayer.h"

@interface ViewController ()

@property (nonatomic, strong) LXAudioRecorder *recorder;
@property (nonatomic, strong) LXAudioPlayer *player;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
}

- (IBAction)beginRecord:(UIButton *)sender {
    if (nil == _recorder) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"a.aac"];
        NSURL *url = [NSURL URLWithString:path];
        _recorder = [[LXAudioRecorder alloc] initWithURL:url];
    }
    [self.recorder record];
}
- (IBAction)stopRecord:(UIButton *)sender {
    [self.recorder stop];
}

- (IBAction)beginPlay:(UIButton *)sender {
    if (nil == _player) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"a.aac"];
        //NSString *path = [[NSBundle mainBundle] pathForResource:@"abc" ofType:@"aac"];
        NSURL *url = [NSURL URLWithString:path];
        _player = [[LXAudioPlayer alloc] initWithURL:url];
    }
    [self.player play];
}
- (IBAction)stopPlay:(UIButton *)sender {
    [self.player stop];
}

@end
