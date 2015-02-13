//
//  UPlayer.m
//  uPlayer
//
//  Created by liaogang on 15/1/27.
//  Copyright (c) 2015年 liaogang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#import "PlayerEngine.h"
#import "PlayerMessage.h"
#import "PlayerTypeDefines.h"
#import "UPlayer.h"

NSTimeInterval CMTime_NSTime( CMTime time )
{
    if (time.timescale == 0) {
        return 0;
    }
    
    return time.value / time.timescale;
}



@interface PlayerEngine ()
{
    PlayState _state;
    BOOL _playTimeEnded;
    dispatch_source_t	_timer;
}
@property (nonatomic,strong) AVPlayer *player;

@end

@implementation PlayerEngine

-(void)needResumePlayAtBoot
{
    PlayerDocument *doc = player().document;
    if (doc.resumeAtReboot && doc.playState != playstate_stopped )
    {
        if ( doc.playState == playstate_playing )
            playTrack( [doc.playerlList getPlayList], [[doc.playerlList getPlayList] getPlayItem]);
        else
            playTrackPauseAfterInit( [doc.playerlList getPlayList], [[doc.playerlList getPlayList] getPlayItem]);
        
        if (doc.playTime > 0)
            [self seekToTime:doc.playTime];
    }
}

-(instancetype)init
{
    self = [super init];
    if (self) {
        
        _playTimeEnded = TRUE;
        
        _state = playstate_stopped;
        
        _playUuid = -1;
        
        self.player = [[AVPlayer alloc]init];
        self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
        
        addObserverForEvent(self, @selector(playNext), EventID_track_stopped_playnext);
        
        addObserverForEvent(self, @selector(playNext), EventID_to_play_next);
        
        addObserverForEvent(self, @selector(needResumePlayAtBoot), EventID_player_document_loaded);
       
        addObserverForEvent(self, @selector(stop), EventID_to_stop);
        addObserverForEvent(self, @selector(playPause), EventID_to_play_pause_resume);
        
        addObserverForEvent(self, @selector(playRandom), EventID_to_play_random);
        
        
        
        
        
        NSNotificationCenter *d =[NSNotificationCenter defaultCenter];
        
        [d addObserver:self selector:@selector(DidPlayToEndTime:) name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
        
        // Update the UI 5 times per second
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, NSEC_PER_SEC / 2, NSEC_PER_SEC / 3);
        
        dispatch_source_set_event_handler(_timer, ^{
            
                if ( [self getPlayState] != playstate_stopped)
                {
                    ProgressInfo *info=[[ProgressInfo alloc]init];
                    info.current =  [self currentTime];
                    info.total = CMTime_NSTime( _player.currentItem.duration );
                    info.fractionComplete= info.current / info.total;
                    
                    postEvent(EventID_track_progress_changed, info);
                }
        });
        
        // Start the timer
        dispatch_resume(_timer);
    }
    
    return self;
}

-(void)DidPlayToEndTime:(NSNotification*)n
{
    _playTimeEnded = TRUE;
    
    [self stop];
    
    postEvent(EventID_track_stopped_playnext, nil);
}

-(void)playNext
{
    PlayerDocument *d = player().document;
    
    PlayerList *list = [d.playerlList getPlayList];
    PlayerTrack *track = [list getPlayItem];
    
    assert(list);
    
    int index = track.index;
    int count = (int)[list count];
    int indexNext =-1;
    PlayOrder order = (PlayOrder)d.playOrder;
    
    if (order == playorder_single) {
        [self stop];
    }
    else if (order == playorder_default)
    {
        indexNext = index +1;
    }
    else if(order == playorder_random)
    {
        static int s=0;
        if(s++==0)
            srand((uint )time(NULL));
        
        indexNext =rand() % (count) - 1;
    }else if(order == playorder_repeat_single)
    {
        indexNext = index;
    }else if(order == playorder_repeat_list)
    {
        indexNext = index + 1;
        if (indexNext == count - 1)
            indexNext = 0;
    }
    
    PlayerTrack* next = nil;
    
    if ( indexNext > 0 && indexNext < [list count] )
        next = [list getItem: indexNext ];
 
    playTrack(list,next);
    
    if( d.trackSongsWhenPlayStarted)
        postEvent(EventID_to_reload_tracklist, nil);
    
}

-(void)dealloc
{
    removeObserver(self);
}

-(PlayState)getPlayState
{
    if ( _playTimeEnded )
    {
        return playstate_stopped;
    }
    else
    {
        if (_player.rate == 0.0) {
            return playstate_paused;
        }
        else //if(_player.rate == 1.0 )
        {
            return playstate_playing;
        }
    }
    
    //return playstate_stopped;
}

-(BOOL)isPlaying
{
    return  (_player.currentItem != nil) && (_player.rate == 1.0) ;
}

-(bool)isPaused
{
    return _player.rate == 0.0;
}

-(bool)isStopped
{
    return _player.currentItem == nil;
}

-(bool)isPending
{
    return _state == playstate_pending;
}

-(void)playRandom
{
    PlayerDocument *d = player().document;
    PlayerList *list = [d.playerlList getPlayList];
    
    if (!list)
        list = [d.playerlList getSelectedList];
    
    assert(list);
    
    int count = (int)[list count];
    
    static int s=0;
    if(s++==0)
        srand((uint )time(NULL));
    
    int indexNext =rand() % (count) - 1;
    
    PlayerTrack* next = nil;
    
    if ( indexNext > 0 && indexNext < [list count] )
        next = [list getItem: indexNext ];
    
    playTrack(list,next);
}

-(void)playPause
{
    if (self.isPlaying) {
        [_player pause];
        _state = playstate_paused ;
        postEvent(EventID_track_paused, nil);
    }
    else if (self.isPaused)
    {
        [_player play];
        _state = playstate_playing ;
        _playTimeEnded = FALSE;
        postEvent(EventID_track_resumed, nil);
    }
    
    
    postEvent(EventID_track_state_changed, nil);
    
}


-(void)seekToTime:(NSTimeInterval)time
{
    [_player seekToTime: CMTimeMakeWithSeconds( time , 1) ];
}

-(NSTimeInterval)currentTime
{
   	CMTime time = _player.currentTime;
    return CMTime_NSTime(time);
}

-(BOOL)playURL:(NSURL *)url pauseAfterInit:(BOOL)pfi
{
     AVPlayerItem *item = [[AVPlayerItem alloc]initWithURL: url];
    [_player replaceCurrentItemWithPlayerItem: item ];
    
    if (pfi == false)
        [_player play];

    _playTimeEnded = FALSE;
    
    postEvent(EventID_track_started, nil);
    postEvent(EventID_track_state_changed, nil);
    
    return 1;
}

-(BOOL)playURL:(NSURL *)url
{
    return [self playURL:url pauseAfterInit:false];
}

- (void)stop
{
    [_player pause];
    [_player replaceCurrentItemWithPlayerItem:nil];
    self.playUuid = -1;
    
    postEvent(EventID_track_stopped, nil);
    postEvent(EventID_track_state_changed, nil);
}

-(PlayStateTime)close
{
    PlayStateTime st;
    st.time =[self currentTime];
    st.state = [self getPlayState];
    [self stop];
    return st;
}

- (void)setVolume:(float)volume
{
    _player.volume = volume;
}

- (float)volume
{
    return  _player.volume;
}

@end



@implementation ProgressInfo



@end
