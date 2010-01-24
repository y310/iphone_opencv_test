//
//  TimeRecorder.m
//  OpenCVTest
//
//  Created by mito on 10/01/24.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TimeRecorder.h"


@implementation TimeRecorder
- (void) dealloc {
	[mTimeArray release];
	[super dealloc];
}

- (id)init {
	if ([super init]) {
		mTimeArray = [[NSMutableArray alloc] init];
	}
	return self;
}

-(void) start {
	mStartTime = [NSDate date];
}

-(double) end {
	double time = [[NSDate date] timeIntervalSinceDate:mStartTime];
	NSNumber *interval = [[NSNumber alloc] initWithDouble:time];
	[mTimeArray addObject:interval];
	[interval release];
	return time;
}

-(void) reset {
	[mTimeArray removeAllObjects];
}

-(double) average {
	double total = 0;
	for (int i = 0; i < [mTimeArray count]; i++) {
		NSNumber *time = [mTimeArray objectAtIndex:i];
		total += [time doubleValue];
	}
	return total / [mTimeArray count];
}
@end
