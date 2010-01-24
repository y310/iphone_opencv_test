//
//  TimeRecorder.h
//  OpenCVTest
//
//  Created by mito on 10/01/24.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface TimeRecorder : NSObject {
	NSDate *mStartTime;
	NSMutableArray *mTimeArray;
}
-(void) start;
-(double) end;
-(void) reset;
-(double) average;
@end
