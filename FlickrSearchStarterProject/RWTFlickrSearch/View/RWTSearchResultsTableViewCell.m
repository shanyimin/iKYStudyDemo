//
//  Created by Colin Eberhardt on 26/04/2014.
//  Copyright (c) 2014 Colin Eberhardt. All rights reserved.
//

#import "RWTSearchResultsTableViewCell.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "RWTFlickrPhoto.h"
#import <SDWebImage/UIImageView+WebCache.h>
@interface RWTSearchResultsTableViewCell ()

@property (weak, nonatomic) IBOutlet UILabel *titleLabel;
@property (weak, nonatomic) IBOutlet UIImageView *imageThumbnailView;
@property (weak, nonatomic) IBOutlet UILabel *favouritesLabel;
@property (weak, nonatomic) IBOutlet UILabel *commentsLabel;
@property (weak, nonatomic) IBOutlet UIImageView *commentsIcon;
@property (weak, nonatomic) IBOutlet UIImageView *favouritesIcon;

@end

@implementation RWTSearchResultsTableViewCell
- (void)bindViewModel:(id)viewModel{
    RWTFlickrPhoto *photo = viewModel;
    
    self.titleLabel.text = photo.title;
    self.imageThumbnailView.contentMode = UIViewContentModeScaleToFill;
    [self.imageThumbnailView setImageWithURL:photo.url];
}

- (void)setParallax:(CGFloat)value{
    self.imageThumbnailView.transform = CGAffineTransformMakeTranslation(0, value);
}
@end
