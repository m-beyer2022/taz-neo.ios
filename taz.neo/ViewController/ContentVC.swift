//
//  ContentVC.swift
//
//  Created by Norbert Thies on 25.09.18.
//  Copyright © 2018 Norbert Thies. All rights reserved.
//

import UIKit
import NorthLib

// A ContentUrl provides a WebView URL for Articles and Sections
public class ContentUrl: WebViewUrl, DoesLog {

  public var content: Content
  public lazy var url: URL = URL(fileURLWithPath: content.path)

  private var loadClosure: (ContentUrl)->()
  private var _isAvailable = false
  public var isAvailable: Bool {
    get {
      guard !_isAvailable else { return true }
      let path = content.dir.path
      for f in content.files {
        if !f.fileNameExists(inDir: path) 
          { self.loadClosure(self); return false }
      }
      _isAvailable = true
      return true
    }
    set {
      _isAvailable = true
      $whenAvailable.notify(sender: self)
    }
  }
  
  @Callback
  public var whenAvailable: Callback<Void>.Store

  public func waitingView() -> UIView? {
    let view = LoadingView()
    view.topText = content.title ?? ""
    view.bottomText = "wird geladen..."
    return view
  }
  
  public init(content: Content, load: @escaping (ContentUrl)->()) {
    self.content = content
    self.loadClosure = load
  }
  
} // ContentUrl

// MARK: - ContentVC
/**
 A ContentVC is a view controller that displays an array of Articles or Sections 
 in a collection of WebViews
 */
open class ContentVC: WebViewCollectionVC, IssueInfo, UIStyleChangeDelegate {

  /// CSS Margins for Articles and Sections
  public class var topMargin: CGFloat { return 40 }
  public static let bottomMargin: CGFloat = 50


  public var feederContext: FeederContext  
  public var delegate: IssueInfo!
  public var contentTable: ContentTableVC?
  public var contents: [Content] = []
  public var feeder: Feeder { delegate.feeder }
  public var issue: Issue { delegate.issue }
  public var feed: Feed { issue.feed }
  public var dloader: Downloader { delegate.dloader }
  lazy var slider:ButtonSlider? = ButtonSlider(slider: contentTable!, into: self)
  /// Whether to show all content images in a gallery
  public var showImageGallery = true
  public var toolBar = ContentToolbar()
  private var toolBarConstraint: NSLayoutConstraint?
  public var backButton = Button<ImageView>()
  public var playButton = Button<ImageView>()
  public var bookmarkButton = Button<ImageView>()
  private var playClosure: ((ContentVC)->())?
  private var bookmarkClosure: ((ContentVC)->())?
  private var backClosure: ((ContentVC)->())?
  public var homeButton = Button<ImageView>()
  private var homeClosure: ((ContentVC)->())?
  public var textSettingsButton = Button<ImageView>()
  private var textSettingsClosure: ((ContentVC)->())?
  public var shareButton = Button<ImageView>()
  private var shareClosure: ((ContentVC)->())?
  private var imageOverlay: Overlay?
  
  var settingsBottomSheet: BottomSheet?
  private var textSettingsVC = TextSettingsVC()
  
  public var header = HeaderView()
  public var isLargeHeader = false
  
  private static var _tazApiCss: File? = nil
  public var tazApiCss: File {
    if ContentVC._tazApiCss == nil 
    { ContentVC._tazApiCss = File(dir: feeder.resourcesDir.path, fname: "tazApi.css") }
    return ContentVC._tazApiCss!
  }
  private static var _tazApiJs: File? = nil
  public var tazApiJs: File {
    if ContentVC._tazApiJs == nil 
    { ContentVC._tazApiJs = File(dir: feeder.resourcesDir.path, fname: "tazApi.js") }
    return ContentVC._tazApiJs!
  }
  
  public func resetIssueList() { delegate.resetIssueList() }  

  /// Write tazApi.css to resource directory
  public func writeTazApiCss(topMargin: CGFloat? = nil,
                             bottomMargin: CGFloat? = nil, callback: (()->())? = nil) {
    let topMargin = topMargin ?? Self.topMargin
    let bottomMargin = bottomMargin ?? Self.bottomMargin
    let dfl = Defaults.singleton
    let textSize = Int(dfl["articleTextSize"]!)!
    let percentageMaxWidth = Int(dfl["articleColumnPercentageWidth"]!)!
    let maxWidth = percentageMaxWidth * 6
    let mediaLimit = max(Int(UIWindow.size.width), maxWidth)
    let colorMode = dfl["colorMode"]
    let textAlign = dfl["textAlign"]
    var colorModeImport: String = ""
    if colorMode == "dark" { colorModeImport = "@import \"themeNight.css\";" }
    let cssContent = """
      \(colorModeImport)
      @import "scroll.css";
      html, body { 
        font-size: \((CGFloat(textSize)*18)/100)px; 
      }
      body {
        padding-top: \(topMargin+UIWindow.topInset/2)px;
        padding-bottom: \(bottomMargin+UIWindow.bottomInset/2)px;
      }
      p {
        text-align: \(textAlign!);
      }
      @media (min-width: \(mediaLimit)px) {
        body #content {
            width: \(maxWidth)px;
            margin-left: \(-maxWidth/2)px;
            position: absolute;
            left: 50%;
          }
        
        div.VerzeichnisArtikel{
          margin-left: 0;
          margin-right: 0;
        }
      }
    """
    File.open(path: tazApiCss.path, mode: "w") { f in f.writeline(cssContent)
      callback?()
    }
  }
  
  /// pageReady is called when the WebView is ready rendering its contents
  private func pageReady(percentSeen: Int, position: Int) {
    debug("Page Ready: index: \(self.index!), percentSeen: \(percentSeen), position: \(position)")
  }
  
  /// Setup JS bridge
  private func setupBridge() {
    self.bridge = JSBridgeObject(name: "tazApi")
    self.bridge?.addfunc("openImage") { [weak self] jscall in
      guard let self = self else { return NSNull() }
      if let args = jscall.args, args.count > 0,
         let img = args[0] as? String {
        let current = self.contents[self.index!]
        let imgVC = ContentImageVC(content: current, delegate: self,
                                   imageTapped: img)
        imgVC.showImageGallery = self.showImageGallery
        self.imageOverlay = Overlay(overlay:imgVC , into: self)
        self.imageOverlay!.maxAlpha = 0.9
        self.imageOverlay!.open(animated: true, fromBottom: true)
        // Inform Application to re-evaluate Orientation for current ViewController
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification,
                                        object: nil)
        self.imageOverlay!.onClose {
          // reset orientation to portrait
          UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
          self.imageOverlay = nil
        }
        imgVC.toClose {
          self.imageOverlay!.close(animated: true, toBottom: true)
        }
      }
      return NSNull()
    }
    self.bridge?.addfunc("pageReady") { [weak self] jscall in
      guard let self = self else { return NSNull() }
      if let args = jscall.args, args.count > 1,
         let sPrecentSeen = args[0] as? String,
         let percentSeen = Int(sPrecentSeen),
         let sPosition = args[1] as? String,
         let position = Int(sPosition) {
        self.pageReady(percentSeen: percentSeen, position: position)
      }
      return NSNull()
    }
    self.bridge?.addfunc("setBookmark") { [weak self] jscall in
      guard let _ = self else { return NSNull() }
      if let args = jscall.args, args.count > 1,
         let name = args[0] as? String,
         let hasBookmark = args[1] as? Int {
        let bm = hasBookmark != 0 
        let arts = StoredArticle.get(file: name)
        if arts.count > 0 { 
          arts[0].hasBookmark = bm 
          ArticleDB.save()
        }
      }
      return NSNull()
    }
    self.bridge?.addfunc("getBookmarks") { [weak self] jscall in
      guard let _ = self else { return NSNull() }
      let arts = StoredArticle.bookmarkedArticles()
      var names: [String] = []
      for a in arts { names += a.html.name }
      return names
    }
  }
  
  /// Write tazApi.js to resource directory
  public func writeTazApiJs() {
    setupBridge()
    let apiJs = """
      var tazApi = new NativeBridge("tazApi");
      tazApi.openUrl = function (url) { window.location.href = url };
      tazApi.openImage = function (url) {
        tazApi.call("openImage", undefined, url)
      };
      tazApi.pageReady = function (percentSeen, position, npages) {
        tazApi.call("pageReady", undefined, percentSeen, position, npages);
      };
      tazApi.setBookmark = function (artName, hasBookmark) {
        tazApi.call("setBookmark", undefined, artName, hasBookmark);
      };
    """
    tazApiJs.string = JSBridgeObject.js + apiJs
  }
  
  /// Define the closure to call when the back button is tapped
  public func onBack(closure: @escaping (ContentVC)->()) 
    { backClosure = closure }
  
  /// Define the closure to call when the bookmark button is tapped
  public func onBookmark(closure: @escaping (ContentVC)->()) 
    { bookmarkClosure = closure }
  
  /// Define the closure to call when the home button is tapped
  public func onSettings(closure: @escaping (ContentVC)->())
    { textSettingsClosure = closure }
  
  /// Define the closure to call when the home button is tapped
  public func onHome(closure: @escaping (ContentVC)->()) 
    { homeClosure = closure }
  
  public func onShare(closure: @escaping (ContentVC)->()) {
    shareClosure = closure
    if playClosure == nil { toolBar.setArticleBar() }
    else { toolBar.setArticlePlayBar() }
  }
  
  public func onPlay(closure: ((ContentVC)->())?) { 
    playClosure = closure
    if closure == nil { toolBar.setArticleBar() }
    else { toolBar.setArticlePlayBar() }
  }
  
  func setupSettingsBottomSheet() {
    settingsBottomSheet = BottomSheet(slider: textSettingsVC, into: self, maxWidth: 500)
    ///was 130 >= 208 //Now 195 => 273//with Align 260 => 338
    settingsBottomSheet?.coverage =  338 + UIWindow.verticalInsets
    
    onSettings{ [weak self] _ in
      guard let self = self else { return }
      self.debug("*** Action: <Settings> pressed")
      if self.settingsBottomSheet?.isOpen ?? false {
          self.settingsBottomSheet?.close()
      }
      else {
        self.settingsBottomSheet?.open()
        self.settingsBottomSheet?.slideDown(130)
      }
      
      self.textSettingsVC.updateButtonValuesOnOpen()
    }

    
    /*onPlay{ [weak self] _ in
      /**
          Issues: on external Control no update
          on currentWebView change not respect current state
       => ToDO's
          -  callback is single and here
          - enqueue speak content
       
        HowTo Play, Stop, Pause???
       - play if nothing or paused
       - stop if index != currentIndex AND Playing => No enqueue is not possible
       ???
       Solutions: Long Tap, Extra Menu with prev & next??
       
       */
      guard let self = self else { return }
      
      if SpeechSynthesizer.sharedInstance.isPaused {
        self.playButton.buttonView.color = .white
        SpeechSynthesizer.sharedInstance.continueSpeaking()
      }
      else if SpeechSynthesizer.sharedInstance.isSpeaking {
        self.playButton.buttonView.color = Const.Colors.ciColor
        SpeechSynthesizer.sharedInstance.pauseSpeaking(at: .word)
      } else {
        self.playButton.buttonView.color = Const.Colors.iOSDark.secondaryLabel
        
        let trackTitle:String = "taz \(self.issue.date.short) \(self.header.miniTitle ?? "")"
        var albumTitle = "Artikel"
        if let content = self.contents.valueAt(self.index ?? 0),
           let contentTitle = content.title{
          albumTitle = contentTitle
        }
        self.currentWebView?.speakHtmlContent(albumTitle: albumTitle, trackTitle: trackTitle){ [weak self] in
          self?.playButton.buttonView.name = "audio"
        }
      }
    }*/
  }
  
//  open override func onPageChange(){
//    SpeechSynthesizer.sharedInstance.stopSpeaking(at: .word)
//    self.playButton.buttonView.name = "audio"
//  }
  
  func setupToolbar() {
    backButton.onPress { [weak self] _ in 
      guard let self = self else { return }
      self.backClosure?(self)
    }
    bookmarkButton.onPress { [weak self] _ in 
      guard let self = self else { return }
      self.bookmarkClosure?(self)
    }
    playButton.onPress { [weak self] _ in
      guard let self = self else { return }
      self.playClosure?(self)
    }
    homeButton.onPress { [weak self] _ in 
      guard let self = self else { return }
      self.homeClosure?(self)
    }
    shareButton.onPress { [weak self] _ in 
      guard let self = self else { return }
      self.shareClosure?(self)
    }
    textSettingsButton.onPress { [weak self] _ in
      guard let self = self else { return }
      self.textSettingsClosure?(self)
    }
    backButton.pinSize(CGSize(width: 35, height: 40))
    shareButton.pinSize(CGSize(width: 30, height: 30))
    textSettingsButton.pinSize(CGSize(width: 30, height: 30))
    playButton.pinSize(CGSize(width: 30, height: 30))
    bookmarkButton.pinSize(CGSize(width: 30, height: 30))
    homeButton.pinSize(CGSize(width: 30, height: 30))
    
    backButton.buttonView.name = "chevron-left"
    backButton.buttonView.imageView.contentMode = .right
    shareButton.buttonView.name = "share"
    textSettingsButton.buttonView.name = "text-settings"
    bookmarkButton.buttonView.name = "star"
    playButton.buttonView.name = "audio"
    homeButton.buttonView.name = "home"

    //.vinset = 0.4 -0.4 do nothing
    //.hinset = -0.4  ..enlarge enorm!  0.4...scales down enorm
    //Adjusting the baseline incereases the icon too much
    
    // shareButton.buttonView.hinset = -0.07
    // textSettingsButton.buttonView.hinset = -0.15
    // textSettingsButton.buttonView.layoutMargins change would be ignored in layout subviews
    
    toolBar.addArticleButton(bookmarkButton, direction: .center)
    toolBar.addArticleButton(Toolbar.Spacer(), direction: .center)
    toolBar.addArticleButton(shareButton, direction: .center)
    toolBar.addArticlePlayButton(Toolbar.Spacer(), direction: .center)
    toolBar.addArticlePlayButton(playButton, direction: .center)
    toolBar.addButton(backButton, direction: .left)
    toolBar.addButton(textSettingsButton, direction: .right)
//    toolBar.addButton(homeButton, direction: .right)
    toolBar.applyDefaultTazSyle()
    toolBar.pinTo(self.view)
    
    backButton.isAccessibilityElement = true
    textSettingsButton.isAccessibilityElement = false //make no sense just for seeing people
    homeButton.isAccessibilityElement = true
    playButton.isAccessibilityElement = true
    shareButton.isAccessibilityElement = true
    playButton.isAccessibilityElement = true
    bookmarkButton.isAccessibilityElement = true
    backButton.accessibilityLabel = "zurück"
    homeButton.accessibilityLabel = "Ausgabenübersicht"
    shareButton.accessibilityLabel = "Teilen"
    playButton.accessibilityLabel = "Vorlesen"
    bookmarkButton.accessibilityLabel = "Lesezeichen"
  }
  
  /// Insert new content at (before) index
  public func insertContent(content: Content, at idx: Int) {
    let curl = ContentUrl(content: content) { [weak self] curl in
      guard let self = self else { return }
      self.dloader.downloadIssueData(issue: self.issue, files: curl.content.files) { err in
        if err == nil { curl.isAvailable = true }
      }
    }
    contents.insert(content, at: idx)
    urls.insert(curl, at: idx)
    collectionView?.insert(at: idx)
  }
  
  /// Delete content at index
  public func deleteContent(at idx: Int) {
    if idx < contents.count { 
      contents.remove(at: idx)
      urls.remove(at: idx)
      collectionView?.delete(at: idx)
    }
  }
  
  /// Define new contents
  public func setContents(_ contents: [Content]) {
    self.contents = contents
    let curls: [ContentUrl] = contents.map { cnt in
      ContentUrl(content: cnt) { [weak self] curl in
        guard let self = self else { return }
        self.dloader.downloadIssueData(issue: self.issue, files: curl.content.files) { err in
          if err == nil { curl.isAvailable = true }
        }
      }
    }
    self.urls = curls
  }
  
  // MARK: - viewDidLoad
  override public func viewDidLoad() {
    super.viewDidLoad()
    writeTazApiCss()
    writeTazApiJs()
    self.view.addSubview(header)
    pin(header.top, to: self.view.top)
    if let cv = collectionView {
      pin(header.left, to: cv.left)
      pin(header.right, to: cv.right)
    } else {
      pin(header.left, to: self.view.left)
      pin(header.right, to: self.view.right)
    }
    pinTopAnchor = header.bottom
    setupSettingsBottomSheet()
    setupToolbar()
    if let sections = issue.sections, sections.count > 1 { setupSlider() }
    
    scrollViewDidScroll{[weak self] offset in
      self?.header.scrollViewDidScroll(offset)
    }
    
    scrollViewDidEndDragging{[weak self] offset in
      self?.header.scrollViewDidEndDragging(offset)
    }
    
    scrollViewWillBeginDragging{[weak self] offset in
      self?.header.scrollViewWillBeginDragging(offset)
    }
    
    whenScrolled { [weak self] ratio in
      if (ratio < 0) { self?.toolBar.hide()}
      else { self?.toolBar.hide(false)}
    }
    
    displayUrls()
    registerForStyleUpdates()
  }
  
  public func setupSlider() {
    if let ct = contentTable {
      let twidth = ct.largestTextWidth
      slider?.maxCoverage = twidth + 3*16.0
    }
    
    slider?.image = UIImage.init(named: "logo")
    slider?.image?.accessibilityLabel = "Inhalt"
    slider?.buttonAlpha = 1.0
    header.leftConstraint?.constant = 8 + (slider?.visibleButtonWidth ?? 0.0)
    ///enable shadow for sliderView
    slider?.sliderView.clipsToBounds = false
  }
  
  public func applyStyles() {
    settingsBottomSheet?.color = Const.SetColor.ios(.secondarySystemBackground).color
    settingsBottomSheet?.handleColor = Const.SetColor.ios(.opaqueSeparator).color
    self.collectionView?.backgroundColor = Const.SetColor.HBackground.color
    self.view.backgroundColor = Const.SetColor.HBackground.color
    self.indicatorStyle = Defaults.darkMode ?  .white : .black
    slider?.sliderView.shadow()
    slider?.button.shadow()
    writeTazApiCss{
      super.reloadAllWebViews()
    }
  }
  
  open override var preferredStatusBarStyle: UIStatusBarStyle {
    return Defaults.darkMode ?  .lightContent : .default
  }
  
  
  override public func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.collectionView?.backgroundColor = Const.SetColor.HBackground.color
    self.view.backgroundColor = Const.SetColor.HBackground.color
  }
  
  override public func viewWillDisappear(_ animated: Bool) {
    slider?.hideLeftBackground()
    super.viewWillDisappear(animated)
    if let svc = self.navigationController?.viewControllers.last as? SectionVC {
      //cannot use updateLayout due strange side effects
      if let sidx = svc.index {
        svc.collectionView?.isHidden = true
        svc.collectionView?.collectionViewLayout.invalidateLayout()
        onMainAfter {
          svc.collectionView?.fixScrollPosition(toIndex: sidx)
          svc.collectionView?.showAnimated(duration: 0.1)
        }
      }
    }
  }
  
  override public func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    slider?.close()
    self.settingsBottomSheet?.close()
    if let overlay = imageOverlay { overlay.close(animated: false) }
  }
  
  public func setup(contents: [Content], isLargeHeader: Bool) {
    setContents(contents)
    self.isLargeHeader = isLargeHeader
    self.contentTable!.feeder = feeder
    self.contentTable!.issue = issue
    self.contentTable!.image = feeder.momentImage(issue: issue)
    self.baseDir = feeder.baseDir.path
    onBack { [weak self] _ in
      self?.debug("*** Action: <Back> pressed")
      self?.navigationController?.popViewController(animated: true)
    }
    onHome { [weak self] _ in
      self?.debug("*** Action: <Home> pressed")
      self?.resetIssueList()
      self?.navigationController?.popToRootViewController(animated: true)
    }
  }
 
  public init(feederContext: FeederContext) {
    self.feederContext = feederContext
    self.contentTable = ContentTableVC.loadFromNib()
    super.init()
    hidesBottomBarWhenPushed = true
  }  
   
  required public init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
}
