//
//  ViewController.m
//  LXAudioQueue
//
//  Created by admin on 2019/8/21.
//  Copyright © 2019 admin. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

#import "LXAudioRecoder.h"
#import "LXAudioPlayer.h"



@interface ViewController ()

@property (nonatomic, strong) LXAudioRecoder *recoder;
@property (nonatomic, strong) LXAudioPlayer *player;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
}

- (IBAction)clickRecoder:(UIButton *)sender {
    if (nil == _recoder) {
        NSString *filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).firstObject stringByAppendingPathComponent:@"temp"];
        _recoder = [[LXAudioRecoder alloc] initWithLocalPath:filePath];
    }
    [self.recoder recoder];
}

- (IBAction)stopRecoder:(UIButton *)sender {
    [self.recoder stop];
}

- (IBAction)clickPlay:(UIButton *)sender {
    if (nil == _player) {
//        NSString *filePath = [[NSBundle mainBundle] pathForResource:@"fukua" ofType:@"mp3"];
        NSString *filePath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true).firstObject stringByAppendingPathComponent:@"temp"];
        _player = [[LXAudioPlayer alloc] initWithLocalPath:filePath];
    }
    [_player play];
}


- (IBAction)topPlay:(UIButton *)sender {
    [self.player stop];
}
@end
