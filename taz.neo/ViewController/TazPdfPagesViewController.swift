//
//  TazPdfPagesViewController.swift
//  taz.neo
//
//  Created by Ringo Müller-Gromes on 18.11.20.
//  Copyright © 2020 Norbert Thies. All rights reserved.
//

import Foundation
import NorthLib
import PDFKit



protocol PdfDownloadDelegate {
  func downloadPdf(_ page:Page, finishedCallback: @escaping ((Bool)->()))
}

// MARK: - ZoomedPdfPageImage
/// A ZoomedPdfPageImage handles PageReference (Page) PDF Files with their first PDF Page
/// - usually they have only 1 Page
public class ZoomedPdfPageImage: ZoomedPdfImage {
  public override var pageType : PdfPageType {
    get {
      switch pageReference?.type {
      case .double:
        return . double
      case .right:
        return .right
      default:
        return .left
      }
    }
    set {}
  }
  var pageReference : Page?
  var issueDir : Dir?
  open override var pageTitle: String? {
    get {
      return pageReference?.title
    }
    set {}
  }
  open override var pdfPage: PDFPage? {
    get {
      if let doc = pageReference?.pdfDocument(inIssueDir: issueDir), doc.pageCount > 0 {
        return doc.page(at: 0)
      }
      return nil
    } 
  }
  
  fileprivate var pdfDownloadDelegate:PdfDownloadDelegate?
  
  public override func renderFullscreenImageIfNeeded(finishedCallback: ((Bool) -> ())?) {
    
    if pdfPage == nil,
       let downloadDelegate = pdfDownloadDelegate,
       let page = self.pageReference {
      downloadDelegate.downloadPdf(page) { success in
        if success == false { finishedCallback?(false); return }
        super.renderFullscreenImageIfNeeded(finishedCallback: finishedCallback)
      }
    }
    super.renderFullscreenImageIfNeeded(finishedCallback: finishedCallback)
  }
  
  convenience init(page:Page, issueDir : Dir?) {
    self.init()
    self.issueDir = issueDir
    self.pageReference = page
    self.sectionTitle = "\(page.type)"
  }
}

// MARK: - NewPdfModel
class NewPdfModel : PdfModel, DoesLog, PdfDownloadDelegate {
  func size(forItem atIndex: Int) -> CGSize {
    if let item = self.item(atIndex: atIndex),
       let pdfPageImage = item as? ZoomedPdfPageImage,
       let page = pdfPageImage.pageReference,
       page.type == .double {
      return panoPageSize ?? PdfDisplayOptions.Overview.fallbackPageSize
    }
    return singlePageSize
  }
  
  
  public func pageIndexForLink(_ link: String) -> Int? {
    let p = images as? [ZoomedPdfPageImage]
    return p?.firstIndex(where: { $0.pageReference?.pdf?.fileName == link }) ?? nil
  }
  
  public func pageIndexForArticle(_ article: Article) -> Int? {
    let p = images as? [ZoomedPdfPageImage]
    return p?.firstIndex(where: { zoomedPdfPageImage in
      zoomedPdfPageImage.pageReference?.frames?
        .first(where: { $0.link?.lastPathComponent == article.path.lastPathComponent}) != nil
    }) ?? nil
  }
  
  private var whenScrolledHandler : WhenScrolledHandler?
  public func whenScrolled(minRatio: CGFloat, _ closure: @escaping (CGFloat) -> ()) {
    whenScrolledHandler = (minRatio, closure)
  }
  
  var title: String?
  var count: Int { get {return images.count}}
  var index: Int = 0
  var issueInfo:IssueInfo?
    
  var defaultRawPageSize: CGSize?
  var singlePageSize: CGSize = .zero
  var panoPageSize: CGSize?
  
  func item(atIndex: Int) -> ZoomedPdfImageSpec? {
    return images.valueAt(atIndex)
  }
  
  var images : [ZoomedPdfImageSpec] = []
  
  var pageMeta : [Int:String] = [:]
  
  var imageSizeMb : UInt64 {
    get{
      var totalSize:UInt64 = 0
      for case let img as ZoomedPdfImage in self.images {
        log("page: \(img.pdfPageIndex ?? -1) size:\(img.image?.mbSize ?? 0)")
        totalSize += UInt64(img.image?.mbSize ?? 0)
      }
      return totalSize
    }
  }
  
  func downloadPdf(_ page: Page, finishedCallback: @escaping ((Bool) -> ())) {
    guard let issueInfo = self.issueInfo, let pdf = page.pdf else { finishedCallback(false); return }
    issueInfo.dloader.downloadIssueFiles(issue: issueInfo.issue,
                                         files: [pdf]) { error in
      finishedCallback(error==nil)
    }
  }
  
  public func thumbnail(atIndex: Int, finishedClosure: ((UIImage?)->())?) -> UIImage? {
    guard let pdfImg = self.item(atIndex: atIndex) as? ZoomedPdfPageImage else {
      return nil
    }
    if let waitingImage = pdfImg.waitingImage {
      return waitingImage
    }
    
    let height = singlePageSize.height
    
    if pdfImg.pdfPage == nil,
       let issueInfo = issueInfo,
       let pageRefPdf = pdfImg.pageReference?.pdf
    {
      //PDF Page Download is needed first
      issueInfo.dloader.downloadIssueFiles(issue: issueInfo.issue, files: [pageRefPdf]) { (_) in
        PdfRenderService.render(item: pdfImg,
                                height: height*UIScreen.main.scale,
                                screenScaled: true,
                                backgroundRenderer: true){ img in
          pdfImg.waitingImage = img
          finishedClosure?(img)
        }
      }
    }
    else {
      PdfRenderService.render(item: pdfImg,
                              height: height*UIScreen.main.scale,
                              screenScaled: true,
                              backgroundRenderer: true){ img in
        pdfImg.waitingImage = img
        finishedClosure?(img)
      }
    }
    return nil
  }
  
  init(issueInfo:IssueInfo?) {
    guard let issueInfo = issueInfo,
          let pages = issueInfo.issue.pages
          else { return }
    let issue = issueInfo.issue
    self.issueInfo = issueInfo
    let issueDir = issueInfo.feeder.issueDir(issue: issue)
    
    /// Use Page 1 Facsimile PDF CropBox  @see: PdfRenderService.swift -> extension PDFPage -> var frame
    let rawPageSize:CGSize
      = issue.pageOneFacsimilePdfPage?.frame?.size
      ?? PdfDisplayOptions.Overview.fallbackPageSize
    
    let fullscreenPageHeight = UIScreen.main.bounds.width * rawPageSize.height / rawPageSize.width
    
    for page in pages {
      let item = ZoomedPdfPageImage(page:page, issueDir: issueDir)
      item.fullScreenPageHeight = fullscreenPageHeight
      item.pdfDownloadDelegate = self
      self.images.append(item)
    }
    
    self.defaultRawPageSize = rawPageSize
    let panoPageWidth
      = PdfDisplayOptions.Overview.sliderWidth
      - 2*PdfDisplayOptions.Overview.sideSpacing
    let singlePageWidth
      = (panoPageWidth - PdfDisplayOptions.Overview.interItemSpacing)/2
    let pageHeight = singlePageWidth * rawPageSize.height / rawPageSize.width
    self.singlePageSize = CGSize(width: singlePageWidth,
                                 height: pageHeight)
    self.panoPageSize = CGSize(width: panoPageWidth,
                               height: pageHeight)
  }
}

// MARK: - TazPdfPagesViewController
/// Provides functionallity to interact between PdfOverviewCollectionVC and Pages with PdfPagesCollectionVC
open class TazPdfPagesViewController : PdfPagesCollectionVC, ArticleVCdelegate, UIStyleChangeDelegate{
  
  public var section: Section?
  
  public var sections: [Section]
  
  @Default("smartBackFromArticle")
  var smartBackFromArticle: Bool
  
  public var article: Article? {
    didSet {
      if smartBackFromArticle == false { return }
      guard let mod = self.pdfModel as? NewPdfModel else { return }
      guard let art = article else { return }
      let i = mod.pageIndexForArticle(art)
      self.index = i
    }
  }
  ///reference to pushed child vc, if any
  var childArticleVC: ArticleVcWithPdfInSlider?
  
  public var article2section: [String : [Section]]
  public func displaySection(index: Int) { log("displaySection not implemented")}
  
  // MARK: - linkPressed
  public func linkPressed(from: URL?, to: URL?) {
    guard let to = to else { return }
    let fn = to.lastPathComponent
    let top = navigationController?.topViewController
    debug("*** Action: Link pressed from: \(from?.lastPathComponent ?? "[undefined]") to: \(fn)")
    if let avc = top as? ArticleVC,
      to.isFileURL,
      issue.article2sectionHtml[fn] != nil {
      avc.gotoUrl(url:to)
    }
    else {
      self.debug("Calling application for: \(to.absoluteString)")
      if UIApplication.shared.canOpenURL(to) {
        UIApplication.shared.open(to, options: [:], completionHandler: nil)
      }
      else {
        error("No application or no permission for: \(to.absoluteString)")
      }
    }
  }
  
  public func closeIssue() {
    self.navigationController?.popViewController(animated: false)
  }
  
  public var feederContext: FeederContext
  
  public var issue: Issue
  
  public func resetIssueList() {
    print("TODO: resetIssueList")
  }
  
  var thumbnailController : PdfOverviewCollectionVC?
  var slider:PdfButtonSlider?
  
  @Default("articleFromPdf")
  public var articleFromPdf: Bool
  
  @Default("fullPdfOnPageSwitch")
  public var fullPdfOnPageSwitch: Bool
 
  // MARK: - updateMenuItems
  func updateMenuItems(updatedSizeIsLandscape: Bool? = nil){
    self.menuItems = [
      ("Artikelansicht",
       articleFromPdf ? "checkmark" : "",
       { [weak self] _ in
        guard let self = self else { return }
        self.articleFromPdf = !self.articleFromPdf
        self.updateMenuItems()
       })]
    
    if App.isAlpha {
      self.menuItems.insert((title: "Zoom 1:1 (⍺)",
                             icon: "1.magnifyingglass",
                             
                             
                             closure: { [weak self] _ in
        if let ziv = self?.currentView as? ZoomedImageView  {
          ziv.scrollView.setZoomScale(1.0, animated: true)
        }
      }), at: 0)
    }

    if updatedSizeIsLandscape == nil && UIWindow.isLandscape
    || updatedSizeIsLandscape != nil && updatedSizeIsLandscape ?? false {
      self.menuItems.append((title: "Breite einpassen",
                            icon: fullPdfOnPageSwitch ? "" : "checkmark",
                            closure: {[weak self] _ in self?.changePageHandling()}))
      self.menuItems.append((title: "ganze Seite",
                            icon: fullPdfOnPageSwitch ? "checkmark" : "",
                            closure: {[weak self] _ in self?.changePageHandling()}))
    }
    
    (self.currentView as? ZoomedImageViewSpec)?.menu.menu = self.menuItems
  }
  
  func changePageHandling(){
    self.fullPdfOnPageSwitch = !self.fullPdfOnPageSwitch
    self.updateMenuItems()
    if let ziv = self.currentView as? ZoomedImageView {
      onMainAfter {   [weak self] in
        self?.applyPageLayout(ziv)
      }
    }
  }
  
  public var toolBar = ContentToolbar()
  
  override public var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }
  
  // MARK: - init
  public init(issueInfo:IssueInfo) {
    Log.minLogLevel = .Debug
    let pdfModel = NewPdfModel(issueInfo: issueInfo)
    
    var title
    = issueInfo.issue.validityDateText(timeZone: issueInfo.feeder.timeZone)
    title = title.replacingOccurrences(of: ", ", with: ",\n")
    title = title.replacingOccurrences(of: "Woche ", with: "Woche\n")
    pdfModel.title = title
    
    
    if let count = issueInfo.issue.pages?.count,
       let lastIndex = issueInfo.issue.lastPage,
       lastIndex < count {
      pdfModel.index = lastIndex
    }
    
    self.sections = issueInfo.issue.sections ?? []
    self.article2section = issueInfo.issue.article2section
    self.feederContext = issueInfo.feederContext
    self.issue = issueInfo.issue
    super.init(data: pdfModel)
    
    hidesBottomBarWhenPushed = true
    
    thumbnailController = PdfOverviewCollectionVC(pdfModel:pdfModel)
    thumbnailController?.collectionView.backgroundColor = Const.Colors.darkSecondaryBG
    thumbnailController?.cellLabelFont = Const.Fonts.titleFont(size: 12)
    thumbnailController?.titleCellLabelFont = Const.Fonts.contentFont(size: 12)
    thumbnailController?.cellLabelLinesCount = 2
    
    self.onTap { [weak self] (oimg, x, y) in
      guard let self = self else { return }
      
      if self.feederContext.isAuthenticated == false || Defaults.expiredAccount {
        self.feederContext.authenticate()
        return
      }
      
      if self.articleFromPdf == false { return }
      guard let zpdfi = oimg as? ZoomedPdfPageImage else { return }
      guard let link = zpdfi.pageReference?.tap2link(x: Float(x), y: Float(y)),
            let path = zpdfi.issueDir?.path else { return }
        
      if let url = URL(string: link), UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return
      }
      else if let pageIdx = pdfModel.pageIndexForLink(link) {
        self.collectionView?.scrollto(pageIdx,animated: true)
        return
      }
      
      let childThumbnailController = PdfOverviewCollectionVC(pdfModel:pdfModel)
      childThumbnailController.cellLabelFont = Const.Fonts.titleFont(size: 12)
      childThumbnailController.titleCellLabelFont = Const.Fonts.contentFont(size: 12)
      childThumbnailController.cellLabelLinesCount = 2
      childThumbnailController.collectionView.backgroundColor = Const.Colors.darkSecondaryBG
      let articleVC = ArticleVcWithPdfInSlider(feederContext: issueInfo.feederContext,
                                               sliderContent: childThumbnailController)
      articleVC.delegate = self
      childThumbnailController.clickCallback = { [weak self] (_, pdfModel) in
        if let newIndex = pdfModel?.index {
          self?.collectionView?.index = newIndex
        }
        articleVC.slider?.close(animated: true) { [weak self] _ in
          self?.navigationController?.popViewController(animated: true)
        }
      }
      articleVC.gotoUrl(path: path, file: link)
      self.navigationController?.pushViewController(articleVC, animated: true)
      self.childArticleVC = articleVC
    }
  }
  
  public required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - viewDidLoad
  open override func viewDidLoad() {
    super.viewDidLoad()
    self.cellVerticalScrollIndicatorInsets = UIEdgeInsets(top: 10,
                                                  left: 0,
                                                  bottom:10,
                                                  right: 0)
    self.cellHorizontalScrollIndicatorInsets = UIEdgeInsets(top: 10,
                                                  left: 0,
                                                  bottom:-UIWindow.bottomInset,
                                                  right: 0)
    
    xButton.isHidden = true
    guard let thumbnailController = thumbnailController else {return }
    thumbnailController.clickCallback = { [weak self] (_, pdfModel) in
      guard let self = self else { return }
      guard let newIndex = pdfModel?.index else { return }
      self.collectionView?.index = newIndex
      self.slider?.close()
    }
    
    onDisplay { [weak self]  (idx, oview) in
      self?.issue.lastPage = idx
      ArticleDB.save()
    }
    
    setupToolbar()
    setupSlider(sliderContent: thumbnailController)
    registerForStyleUpdates()
  }
  
  // MARK: - setupSlider
  func setupSlider(sliderContent:UIViewController){
    slider = PdfButtonSlider(slider: sliderContent, into: self)
    guard let slider = slider else { return }
    slider.sliderView.clipsToBounds = false
    slider.image = UIImage.init(named: "logo")
    slider.image?.accessibilityLabel = "Inhalt"
    slider.buttonAlpha = 1.0
    slider.hideButtonOnClose = true
    slider.button.additionalTapOffset = 50
    slider.close()
  }
  
  // MARK: - viewWillAppear
  open override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.pageControl?.layer.shadowColor = UIColor.lightGray.cgColor
    self.pageControl?.layer.shadowRadius = 3.0
    self.pageControl?.layer.shadowOffset = CGSize(width: 0, height: 0)
    self.pageControl?.layer.shadowOpacity = 1.0
    self.pageControl?.pageIndicatorTintColor = UIColor.white
    self.pageControl?.currentPageIndicatorTintColor = Const.SetColor.CIColor.color
    
    if let thumbCtrl = self.thumbnailController {
      var insets = UIWindow.keyWindow?.safeAreaInsets ?? UIEdgeInsets.zero
      insets.bottom += toolBar.totalHeight
      thumbCtrl.collectionView.contentInset = insets
    }
    updateSlidersWidth()
    self.updateMenuItems()
  }
  
  public override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    updateSlidersWidth(size.width)
    updateMenuItems(updatedSizeIsLandscape: size.width > size.height)
  }
  
  func updateSlidersWidth(_ newParentWidth : CGFloat? = nil){
    let sliderWidth = min(UIScreen.main.bounds.size.width,
                          UIScreen.main.bounds.size.height,
                          newParentWidth ?? UIScreen.main.bounds.size.width,
                          500)
    ///formally lInset = UIWindow.safeInsets.left was added
    ///but after rotation this is not yet the right value because viewWillTransition is called before
    ///UIWindow.safeInsets are changed
    if let slider = self.slider,
       let newSliderWidth = (sliderWidth - slider.button.frame.size.width) as CGFloat?{
      slider.coverage = newSliderWidth
      slider.updateSliderWidthIfNeeded(newSliderWidth)

    }
    childArticleVC?.updateSlidersWidth(sliderWidth: sliderWidth)
  }
  
  // MARK: - setupViewProvider
  open override func setupViewProvider(){
    super.setupViewProvider()
    onDisplay { [weak self] (idx, optionalView) in
      guard let ziv = optionalView as? ZoomedImageView,
            let pdfImg = ziv.optionalImage as? ZoomedPdfImageSpec else { return }
      ziv.menu.menu = self?.menuItems ?? []
      ziv.scrollView.contentInset = .zero //no more need bottom inset
      if ziv.imageView.image == nil
      {
        ziv.optionalImage = pdfImg
        ziv.imageView.image = pdfImg.image
        if pdfImg.image != nil { self?.applyPageLayout(ziv)}
        pdfImg.renderFullscreenImageIfNeeded { [weak self] success in
          self?.handleRenderFinished(success, ziv)
        }
      }
      else {
        self?.applyPageLayout(ziv)
      }

      ziv.whenZoomed {   [weak self] zoomedIn in
        self?.toolBar.show(show:!zoomedIn, animated: true)
      }
      self?.toolBar.show(show:true, animated: true)
    }
  }

  func applyPageLayout(_ ziv:ZoomedImageView){
    guard let pdfImg = ziv.optionalImage as? ZoomedPdfImageSpec else {
      ziv.invalidateLayout()
      return
    }
    
    if UIWindow.isPortrait, pdfImg.pageType == .double {
      //isPortrait && double => fitHeight
      ziv.zoomToFitHeight()
      
    }
    else if UIWindow.isPortrait {
      //isPortrait && !double => fitWidth
      ziv.invalidateLayout()
    }
    else if self.fullPdfOnPageSwitch {
      //Landscape && fullPage Setting => fitHeight
      ziv.zoomToFitHeight()
    }
    else if pdfImg.pageType == .double  {
      //Landscape && !fullPage Setting && double Page => fitWidth of half Page
      ziv.zoomToFitHalfWidth()
    }
    else {
      //Landscape && !fullPage Setting && single Page => fitWidth
      ziv.zoomToFitWidth()
    }
    ziv.scrollToTopLeft()
  }
  
  public override func handleRenderFinished(_ success:Bool, _ ziv:ZoomedImageView){
    if success == false { return }
    onMain { [weak self] in
      self?.applyPageLayout(ziv)
    }
  }
  
  open override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    if parent == nil {
      if let nModel = self.pdfModel as? NewPdfModel {
        nModel.images = []
      }
      self.pdfModel = nil
      thumbnailController?.clickCallback = nil
      thumbnailController = nil
      slider = nil
      self.childArticleVC = nil
    }
  }
  
  // MARK: - viewDidDisappear
  override public func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    slider?.close()
  }
  
  // MARK: - viewDidAppear
  override public func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Notification.send(Const.NotificationNames.articleLoaded)
  }
  
  // MARK: - UIStyleChangeDelegate
  public func applyStyles() {
    slider?.sliderView.shadow()
    slider?.button.shadow()
  }
  
  private var shareButton: Button<ImageView>?
  
  // MARK: - setupToolbar
  func setupToolbar() {
    //the button tap closures
    let onHome:((ButtonControl)->()) = { [weak self] _ in
      self?.navigationController?.popViewController(animated: true)
    }
    
    let onShare:((ButtonControl)->()) = { [weak self] _ in
      guard let self = self,
            let i = self.index,
            let pi = self.pdfModel?.item(atIndex:i) as? ZoomedPdfPageImage,
            let page = pi.pageReference?.pagina,
            let url = pi.pageReference?.pdfDocument(inIssueDir: self.issue.dir)?.documentURL else { return }
      let filename = "taz_\(self.issue.date.filename)_S-\(page).pdf"
      let tempUrl = NSTemporaryDirectory() + filename
      let cp = File(url).copy(to:tempUrl, isOverwrite: true)
      let tmpFile = File(dir: NSTemporaryDirectory(), fname: filename).url
      
      let dialogue = ExportDialogue<Any>()
      dialogue.present(item: tmpFile,
                       view: self.shareButton ?? self.toolBar,
                       subject: "taz vom \(self.issue.date.short) Seite \(page)")
    }
    
    //the buttons and alignments
    _ = toolBar.addImageButton(name: "home",
                               onPress: onHome,
                               direction: .right,
                               accessibilityLabel: "Übersicht")
    _ = toolBar.addImageButton(name: "chevron-left",
                               onPress: onHome,
                               direction: .left,
                               accessibilityLabel: "Zurück",
                               width: 35,
                               height: 40,
                               contentMode: .right)
    
    if App.isAvailable(.FAKSIMILEEXPORT)
      || (DefaultAuthenticator.getUserData().id ?? "").hasSuffix("@taz.de") {
      shareButton = toolBar.addImageButton(name: "share",
                                 onPress: onShare,
                                 direction: .center,
                                 accessibilityLabel: "Teilen")
    }
    
    //the toolbar setup itself
    toolBar.applyDefaultTazSyle()
    toolBar.pinTo(self.view)
    
    if let pc = self.pageControl, let sv = pc.superview {
      for constraint in sv.constraints {
        if constraint.firstItem as? UIView == pc,
           constraint.firstAnchor.isKind(of: NSLayoutYAxisAnchor.self) {
          constraint.isActive = false
        }
      }
      pin(pc.bottom, to: toolBar.top, dist: -10, priority: .required)
    }
    
    self.whenScrolled(minRatio: 0.01) { [weak self] ratio in
      if ratio < 0 { self?.toolBar.show(show:false, animated: true)}
      else { self?.toolBar.show(show:true, animated: true)}
    }
  }
}


// MARK: - Class ArticleVcWithPdfInSlider
class ArticleVcWithPdfInSlider : ArticleVC {
  
  var sliderContent: UIViewController?
  
  public init(feederContext: FeederContext, sliderContent:UIViewController) {
    self.sliderContent = sliderContent
    super.init(feederContext: feederContext)
  }
  
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func setupSlider() {
    if let sContent = self.sliderContent {
      self.slider = ButtonSlider(slider: sContent, into: self)
    }
    super.setupSlider()
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    updateSlidersWidth(sliderWidth: self.view.frame.size.width)
  }
  
  func updateSlidersWidth(sliderWidth : CGFloat){
    let sliderWidth = min(sliderWidth, 500)
    guard let buttonWidth = slider?.button.frame.size.width,
            let coverage = (sliderWidth - buttonWidth) as CGFloat? else {  return }
    slider?.coverage = coverage
    slider?.updateSliderWidthIfNeeded(coverage)
  }
  
  override func willMove(toParent parent: UIViewController?) {
    if parent == nil {
      self.slider?.close()
    }
    super.willMove(toParent: parent)
  }
  
  override func didMove(toParent parent: UIViewController?) {
    super.didMove(toParent: parent)
    if parent == nil {
      if let thumbCtrl = self.sliderContent as? PdfOverviewCollectionVC {
        thumbCtrl.clickCallback = nil
      }
      NotificationCenter.default.removeObserver(self)
      contentTable = nil
      sliderContent = nil
      delegate = nil
      self.slider = nil
      self.settingsBottomSheet = nil
    }
  }
}


/// Custom Child class to get rid of the slider width bug e.g. in PDF Pages Slider
/// Bug: Open PDF Rotate 90°, 180°, 90°, wait each animation, now were back open Slider => wrong size due
/// coverage calculated with iPhone Screen height instead width
/// Slider coverage calculates with saved coverageration => multiple issues are here
class PdfButtonSlider: ButtonSlider {
  var _coverage: CGFloat = UIScreen.main.bounds.size.width
  
  override var coverage: CGFloat {
    get { return _coverage }
    set {
      _coverage = newValue
      resetConstraints()
    }
  }
}
