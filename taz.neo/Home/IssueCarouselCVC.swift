//
//  NewIssueCVC.swift
//  taz.neo
//
//  Created by Ringo Müller on 30.01.23.
//  Copyright © 2023 Norbert Thies. All rights reserved.
//

import UIKit
import NorthLib


class IssueCarouselCVC: UICollectionViewController {
  
  @Default("showBottomTilesAnimation")
  public var showBottomTilesAnimation: Bool
  
  @Default("bottomTilesAnimationLastShown")
  public var bottomTilesAnimationLastShown: Date
  
  @Default("bottomTilesLastShown")
  public var bottomTilesLastShown: Date
  
  @Default("bottomTilesShown")
  public var bottomTilesShown: Int {
    didSet { if bottomTilesShown > 10 { showBottomTilesAnimation = false }  }
  }
  
  private var topStatusButtonConstraint:NSLayoutConstraint?
  private var statusWrapperBottomConstraint: NSLayoutConstraint?
  private var statusWrapperWidthConstraint:NSLayoutConstraint?
  
  /// Animation for ScrollDown
  var scrollDownAnimationView: ScrollDownAnimationView?
  
  public var pullToLoadMoreHandler: (()->())?
  private static let reuseCellId = "issueCollectionViewCell"
  
  var lastCenterIndex: Int?
  
  var centerIndex: Int? {
    guard let cv = collectionView else { return nil }
    let center = self.view.convert(cv.center, to: cv)
    return cv.indexPathForItem(at: center)?.row
  }
  
  let downloadButton = DownloadStatusButton()
  let dateLabel = CrossfadeLabel()
  
  lazy var bottomItemsWrapper: UIView = {
    let v = UIView()
    v.addSubview(downloadButton)
    v.addSubview(dateLabel)
    statusWrapperWidthConstraint = v.pinWidth(0)
    dateLabel.contentFont().white()
    dateLabel.textAlignment = .center
    pin(downloadButton.right, to: v.right)
    downloadButton.centerY()
    pin(dateLabel.left, to: v.left, dist: 25)
    pin(dateLabel.right, to: v.right, dist: -25)
    dateLabel.centerY()
    v.pinHeight(30)
    
    dateLabel.onTapping { _ in
      
    }
    
    return v
  }()
  
  
  lazy var statusHeader = StatusHeader()

  var service: IssueOverviewService
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Uncomment the following line to preserve selection between presentations
    // self.clearsSelectionOnViewWillAppear = false
    
    // Register cell classes
    self.collectionView!.register(IssueCollectionViewCell.self,
                                  forCellWithReuseIdentifier: Self.reuseCellId)
    self.collectionView.backgroundColor = .black
    
    self.view.addSubview(bottomItemsWrapper)
    bottomItemsWrapper.centerX()
    statusWrapperBottomConstraint = pin(bottomItemsWrapper.top, to: self.view.bottom, dist: 0)
    setupPullToRefresh()
  }
    
  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    if lastCenterIndex == nil { lastCenterIndex = centerIndex}
    super.viewWillTransition(to: size, with: coordinator)
    onMain{[weak self] in
      guard let idx = self?.lastCenterIndex else { return }
      self?.lastCenterIndex = nil
      self?.collectionView.scrollToItem(at: IndexPath(row: idx, section: 0),
                      at: .centeredHorizontally,
                      animated: true)
    }
  }
    

  override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
    if let handler = pullToLoadMoreHandler,
       scrollView.contentOffset.x < -50 {
      handler()
    }
  }
   
  
  override func scrollViewDidScroll(_ scrollView: UIScrollView) {
    bottomItemsWrapper.isUserInteractionEnabled = false
    dateLabel.alpha = 0.2
    downloadButton.alpha = 0.5
  }
  
  ///Stop fix offset IS VERRY SLOW HERE for manuell stops
  override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
    ///Problem scrolle oder springe (und ggf scrolle) DONE
    ///komme an index wo nur das Datum aber nicht das issue bekannt ist
    ///kein issue => zeige download wolke TODO
    ///issue zeige zustand und richtiges datum (wochentaz) TODO
    ///...
    ///war kein issue da..kommt dann rein...refresh date TODO
    guard let idx = centerIndex,
          let date = service.date(at: idx) else { return }
    let issue = service.issue(at: date)
    let txt
    = issue?.validityDateText(timeZone: GqlFeeder.tz,
                              short: true)
    ?? date.short
    dateLabel.setText(txt)
    downloadButton.setStatus(from: issue)
    downloadButton.alpha = 1.0
    
        guard let centerIndex else { return }
        self.collectionView.scrollToItem(at: IndexPath(row: centerIndex, section: 0),
                                         at: .centeredHorizontally,
                                         animated: true)
    
  }
    
  // MARK: UICollectionViewDataSource
  
  override func numberOfSections(in collectionView: UICollectionView) -> Int {
    return 1
  }
  
  override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return service.issueDates.count
  }
  
  override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: Self.reuseCellId,
      for: indexPath)
    guard let cell = cell as? IssueCollectionViewCell,
          let data = service.cellData(for: indexPath.row) else { return cell }
    cell.date = data.date
    cell.issue = data.issue
    cell.image = data.image
    return cell
  }
  
  // MARK: > Cell Click/Select
  public override func collectionView(_ collectionView: UICollectionView,
                                      didSelectItemAt indexPath: IndexPath) {
    guard let issue = self.service.getIssue(at: indexPath.row) else {
      error("Issue not available try later")
      return
    }
    (parent as? OpenIssueDelegate)?.openIssue(issue)
  }
  
  public override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
  }
  
  public init(service: IssueOverviewService) {
    self.service = service
    let layout = IssueCarouselFlowLayout()
    layout.scrollDirection = .horizontal
    layout.sectionInset = .zero
    layout.minimumInteritemSpacing = 1000000.0
    
    super.init(collectionViewLayout: layout)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}


extension IssueCarouselCVC {
  func reloadVisibleCells() {
    let vips = self.collectionView.indexPathsForVisibleItems
    for ip in vips {
      _ = self.collectionView.cellForItem(at: ip)
    }
    //is faster tested with iPadOS 16.2 iPad Pro 2 Simulators same
    // Data/environment; code change if false,... Lamdscape
    // reconfigure feels ~1/3 faster
    // @see: https://swiftsenpai.com/development/cells-reload-improvements-ios-15/
    if #available(iOS 15.0, *) {
      self.collectionView.reconfigureItems(at: vips)
    } else {
      UIView.performWithoutAnimation {
        self.collectionView.reloadItems(at: vips)
      }
    }
  }
}

extension IssueCarouselCVC {
  func updateCarouselSize(_ size:CGSize, horizontalSizeClass:UIUserInterfaceSizeClass){
    guard let layout = self.collectionView.collectionViewLayout as? CarouselFlowLayout else { return }
    let defaultPageRatio:CGFloat = 0.670219
    
    var sideInset = 0.0
    var cw: CGFloat//cellWidth
    //https://developer.apple.com/design/human-interface-guidelines/foundations/layout/
    if horizontalSizeClass == .compact && size.width < size.height * 0.6 {
      cw = size.width*0.6
      let h = cw/defaultPageRatio
      layout.itemSize = CGSize(width: cw, height: h)
      layout.minimumLineSpacing //= 60.0
      = size.width*0.155//0.3/2 out of view bei 0.4/2
      sideInset = (size.width - cw)/2
    } else {
      //Moments are 660*985
      let h = min(size.height*0.5, 985*UIScreen.main.scale)
      cw = h*defaultPageRatio
      layout.itemSize = CGSize(width: cw, height: h)
      layout.minimumLineSpacing //= 60.0
      = cw*0.3//0.3/2 out of view bei 0.4/2
      sideInset = (size.width - cw)/2
    }

    let  offset = 0.5*( size.height
             - UIWindow.topInset
             - layout.maxScale*layout.itemSize.height) - 10
//    print("dist is: -0,5* (\(size.height)   -   \(UIWindow.topInset)   -   \(layout.maxScale*layout.itemSize.height))=\(statusWrapperBottomConstraint?.constant ?? 0)\n  0.5 * ( size.height - UIWindow.safeInsets.top - HomeTVC.defaultHeight - layout.maxScale*layout.itemSize.height)")
    
    topStatusButtonConstraint?.constant = offset
    statusWrapperBottomConstraint?.constant = -offset
    statusWrapperWidthConstraint?.constant = cw*layout.maxScale
    
    self.collectionView.contentInset
    = UIEdgeInsets(top:0,left:sideInset,bottom:0,right:sideInset)
    
  }
  
}


extension IssueCarouselCVC {
  
  fileprivate func setupPullToRefresh() {
    //add status Header
    self.view.addSubview(statusHeader)
    pin(statusHeader.left, to: self.view.left)
    pin(statusHeader.right, to: self.view.right)
    topStatusButtonConstraint = pin(statusHeader.bottom, to: self.view.top, dist: 0)
    #warning("ToDo check for new issues implementation and remove status")
    #warning("ToDo statusHeader is wrong pos")
    statusHeader.currentStatus = .fetchNewIssues
    statusHeader.onTapping { [weak self] _ in
    }
    /**
     issueCarousel.onLabelTap { idx in
       self.showDatePicker()
     }
     */
    
    
//    Notification.receive("checkForNewIssues", from: issueVC.feederContext) { notification in
//      if let status = notification.content as? StatusHeader.status {
//        print("receive status: \(status)")
//        self.statusHeader.currentStatus = status
//      }
//    }
    self.pullToLoadMoreHandler = {   [weak self] in
      self?.statusHeader.currentStatus = .fetchNewIssues
      URLCache.shared.removeAllCachedResponses()
      self?.service.checkForNewIssues()
    }
  }
}


// MARK: - showScrollDownAnimationIfNeeded
extension IssueCarouselCVC {
  
  
  /// shows an animation to generate the user's interest in the lower area
  ///  **Requirements to show animation:**
  ///
  ///  **showBottomTilesAnimation** ConfigDefault is true
  ///  **bottomTilesLastShown** is at least 24h ago
  ///  **bottomTilesAnimationLastShown** is at least 30s ago
  ///  - no active animation
  ///
  /// - Parameter delay: delay after animation started if applicable
  func showScrollDownAnimationIfNeeded(delay:Double = 2.0) {
    if showBottomTilesAnimation == false { return }
    guard (Date().timeIntervalSince(bottomTilesLastShown) >= 60*60*24) &&
          (Date().timeIntervalSince(bottomTilesAnimationLastShown) >= 30)
    else { return }
    
    if scrollDownAnimationView == nil {
      scrollDownAnimationView = ScrollDownAnimationView()
    }
    
    guard let scrollDownAnimation = scrollDownAnimationView else {
      return
    }
    
    if scrollDownAnimation.superview == nil {
      self.view.addSubview(scrollDownAnimation)
      scrollDownAnimation.centerX()
      pin(scrollDownAnimation.bottom, to: self.view.bottomGuide(), dist: -12)
    }
    
    onMainAfter(delay) {   [weak self] in
      self?.scrollDownAnimationView?.animate()
      self?.bottomTilesAnimationLastShown = Date()
    }
  }
}