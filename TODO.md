#  TODO taz.neo

Things that should be done soon

## Important before next release
- IssueVcWithBottomTiles:
    - Test: scrolling or stocking if new items added (insertItems)
    - may Refactor & Integrate both Controller after merge
    - Cloud Icon disapear on Download finish

### ToDO's in Source
/Users/taz/src/TAZ/taz-neo.ios/taz.neo/Feedback/FeedbackViewController.swift: 
//#warning("ToDo: 0.9.4 ToDo implement send by mail if offline, in prev versions nothing happen, now alert will be shown")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/AppDelegate.swift:  
//#warning("ToDo: 0.9.4 Server Switch without App Restart")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/FeederContext.swift:      
//#warning("ToDo: 0.9.4 loock for logs&errors after 0.9.3 release")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/FeederContext.swift:  
//#warning("ToDo: 0.9.4 fix App crash if called when active downloads")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/ViewController/TextSettingsVC.swift:      
//#warning("ToDo 0.9.4: use Helper.swift Defaults.articleTextSize functions @see Settings")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/ViewController/SettingsVC.swift:        
//#warning("ToDo: 0.9.4 enable resume of feederCOntext / Re-Init here")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/FeederContext.swift:              
//#warning("ToDo 0.9.4+: Missing Update of an stored Issue")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/ViewController/ArticleVC.swift:      
//#warning("ToDo: 0.9.4+ Implement Search")

/Users/taz/src/TAZ/taz-neo.ios/taz.neo/BookmarkFeed.swift:    
//#warning("ToDo: 0.9.4+ @Ringo: Build Section-HTML here")


## Less-Important keep in mind for future releases

- IssueVcWithBottomTiles: 
  - line 246  collectionView.cellForItemAt :: issueVC.feeder.momentImage(issue: issue)
    image is 2.4MB currently may use smaller to increase Performance
    especially with BottomTiles (8 and more images at the same time)
    Check with: print("Moment Image Size: \(img.mbSize) for: \(img) with scale: \(img.scale)")
