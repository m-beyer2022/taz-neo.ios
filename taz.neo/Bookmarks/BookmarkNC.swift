//
//  BookmarkNC.swift
//  taz.neo
//
//  Created by Ringo Müller on 12.05.22.
//  Copyright © 2022 Norbert Thies. All rights reserved.
//

import UIKit
import NorthLib

fileprivate class PlaceholderVC: UIViewController{
  override func viewDidLoad() {
    super.viewDidLoad()
    self.view
    = PlaceholderView("Die Leseliste ist leer!",
                      image: UIImage(named: "star"))
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    self.view.backgroundColor = Const.SetColor.CTBackground.color
  }
}

class BookmarkNC: NavigationController {
  
  /// Are we in facsimile mode
  @Default("isFacsimile")
  public var isFacsimile: Bool
  
  private var placeholderVC = PlaceholderVC()
  
  public var feederContext: FeederContext
  public lazy var bookmarkFeed = BookmarkFeed.allBookmarks(feeder: feeder)
  public var issue: Issue { bookmarkFeed.issues![0] }
  var isShowingAlert = false
  
  public lazy var sectionVC: BookmarkSectionVC = {
    return createSectionVC()
  }()
  
  func createSectionVC(openArticleAtIndex: Int? = nil) -> BookmarkSectionVC{
    let svc = BookmarkSectionVC(feederContext: feederContext,
                               atSection: nil,
                               atArticle: openArticleAtIndex)
    svc.delegate = self
    svc.toolBar.show(show:false, animated: true)
    svc.isStaticHeader = true
    svc.header.titletype = .bigLeft
    svc.header.title = "leseliste"
    svc.hidesBottomBarWhenPushed = false
    return svc
  }
  
  func setup() {
    Notification.receive(Const.NotificationNames.expiredAccountDateChanged) { [weak self] notif in
      guard self?.feeder.isAuthenticated ?? false else { return }
      guard Defaults.expiredAccount == false else { return }
      self?.reloadOpened()
    }
    
    Notification.receive("updatedDemoIssue") { [weak self] notif in
      guard let self = self else { return }
      self.bookmarkFeed
      = BookmarkFeed.allBookmarks(feeder: self.feeder)
      self.sectionVC.delegate = nil
      self.sectionVC.delegate = self///trigger SectionVC.setup()
    }
    
    Notification.receive("BookmarkChanged") { [weak self] msg in
      // regenerate all bookmark sections
      guard let emptyRoot = self?.placeholderVC,
            let self = self else { return }
      if let art = msg.sender as? StoredArticle {
        self.bookmarkFeed.loadAllBookmarks()
        self.bookmarkFeed.genAllHtml()
        if art.hasBookmark {
          self.sectionVC.insertArticle(art)
          self.sectionVC.reload()
          self.ensureBookmarkListVisibleIfNeeded(animated: false)
        }
        else {
          self.sectionVC.deleteArticle(art)
          if !self.sectionVC.isVisible { self.sectionVC.reload() }
        }
        if self.bookmarkFeed.count <= 0 {
          self.viewControllers[0] = emptyRoot
          self.popToRootViewController(animated: true)
        }
      }
      else {
        self.bookmarkFeed.genAllHtml()
        self.sectionVC.reload()
      }
    }
  }
  
  func ensureBookmarkListVisibleIfNeeded(animated: Bool = true){
    if bookmarkFeed.count > 0 && self.viewControllers.first != sectionVC  {
      setViewControllers([sectionVC], animated: animated)
    }
  }
   
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    ensureBookmarkListVisibleIfNeeded()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    setup()
  }
  
  init(feederContext: FeederContext) {
    self.feederContext = feederContext
    super.init(rootViewController: placeholderVC)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

extension BookmarkNC: IssueInfo {
  public func resetIssueList() {}
}


extension BookmarkNC: ReloadAfterAuthChanged {
  public func reloadOpened(){
    let lastIndex: Int? = (self.viewControllers.last as? ArticleVC)?.index
    var issuesToDownload:[StoredIssue] = []
    for art in bookmarkFeed.issues?.first?.allArticles ?? [] {
      if let sissue = art.primaryIssue as? StoredIssue,
         sissue.status == .reduced,
         issuesToDownload.contains(sissue) == false {
        issuesToDownload.append(sissue)
      }
    }
        
    func downloadNextIfNeeded(){
      if let nextIssue = issuesToDownload.first {
        self.feederContext.getCompleteIssue(issue: nextIssue,
                                             isPages: isFacsimile,
                                             isAutomatically: false)
      } else if let idx = lastIndex {
        self.bookmarkFeed
        = BookmarkFeed.allBookmarks(feeder: self.feeder)
        self.sectionVC.relaese()
        self.sectionVC
        = createSectionVC(openArticleAtIndex: idx)
        self.viewControllers[0] = self.sectionVC
        self.popToRootViewController(animated: true)
        Notification.send(Const.NotificationNames.removeLoginRefreshDataOverlay)
      } else {
        self.bookmarkFeed
        = BookmarkFeed.allBookmarks(feeder: self.feeder)
        self.sectionVC.reload()
      }
    }
    
    Notification.receive("issue"){ notif in
      ///ensure the issue download comes from here!
      guard let issue = notif.object as? Issue else { return }
      guard let issueIdx = issuesToDownload.firstIndex(where: {$0.date == issue.date})
      else { return /* Issue Download from somewhere else */ }
      issuesToDownload.remove(at: issueIdx)
      downloadNextIfNeeded()
    }
    downloadNextIfNeeded()
  }
}
