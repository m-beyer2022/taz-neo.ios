//
//  HeaderView.swift
//
//  Created by Norbert Thies on 12.01.20.
//  Copyright © 2020 Norbert Thies. All rights reserved.
//

import UIKit
import NorthLib

enum TitleType { case bigLeft, article, section, section0, search  }

/// The Header to show on top of sections and articles
open class HeaderView: UIView,  Touchable {
  let maxOffset = 40.0
  
  private var beginScrollOffset: CGFloat?
  
  //vars
  var title: String? {
    get{ return titleLabel.text }
    set{ titleLabel.text = newValue }
  }
  var subTitle: String? {
    get{ return subTitleLabel.text }
    set{
      subTitleLabel.text = newValue
      updateUI()
    }
  }
  var pageNumber: String? {
    get{ return pageNumberLabel.text }
    set{ pageNumberLabel.text = newValue }
  }
  
  var titletype: TitleType = .bigLeft {
    didSet {
      switch titletype {
        case .bigLeft:
          pageNumberLabel.isHidden = true
          subTitleLabel.isHidden = true
          titleLeftConstraint?.constant = 3.0
          titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          pageNumberLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          titleLabel.textAlignment = .left
          titleFontSizeDefault = Const.Size.LargeTitleFontSize
          titleTopIndentL = Const.Size.DefaultPadding - 11.0
          titleBottomIndentL = -18
        case .article:
          pageNumberLabel.isHidden = false
          subTitleLabel.isHidden = true
          titleLeftConstraint?.constant = 8.0
          titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          pageNumberLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          titleLabel.textAlignment = .right
          pageNumberLabel.textAlignment = .right
          subTitleLabel.textAlignment = .right
          titleFontSizeDefault = Const.Size.DefaultFontSize
          titleTopIndentL = Const.Size.DefaultPadding
          titleBottomIndentL = -8
        case .section:
          pageNumberLabel.isHidden = true
          subTitleLabel.isHidden = false
          titleLeftConstraint?.constant = 8.0
          titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          pageNumberLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          titleLabel.textAlignment = .right
          pageNumberLabel.textAlignment = .right
          subTitleLabel.textAlignment = .right
          titleFontSizeDefault = Const.Size.TitleFontSize
          titleTopIndentL = Const.Size.DefaultPadding
          titleBottomIndentL = -31
        case .section0:
          pageNumberLabel.isHidden = true
          subTitleLabel.isHidden = false
          titleLeftConstraint?.constant = 8.0
          titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          pageNumberLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          titleLabel.textAlignment = .right
          pageNumberLabel.textAlignment = .right
          titleFontSizeDefault = Const.Size.LargeTitleFontSize
          titleTopIndentL = Const.Size.DefaultPadding - 11.0
          titleBottomIndentL = -31
        case .search:
          pageNumberLabel.isHidden = false
          subTitleLabel.isHidden = false
          titleLeftConstraint?.constant = 8.0
          titleLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
          pageNumberLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
          titleLabel.textAlignment = .right
          pageNumberLabel.textAlignment = .left
          titleFontSizeDefault = Const.Size.DefaultFontSize
          titleTopIndentL = Const.Size.DefaultPadding
          titleBottomIndentL = -31
      }
      titleLabel.titleFont(size: titleFontSizeDefault)
      updateUI()
    }
  }
  
  private var titleFontSizeDefault: CGFloat = Const.Size.TitleFontSize
  //FontSize * 1.17 == LabelHeight with our Font
  private var titleFontSizeMini: CGFloat = 12.0
  private let subTitleFontSizeDefault: CGFloat = Const.Size.DefaultFontSize//16
  private var subTitleFontSizeMini: CGFloat = 12.0
  
  //ui
  var titleLabel = Label()
  var line = DottedLineView()
  var subTitleLabel = Label()
  var pageNumberLabel = HidingLabel()
  var borderView:UIView?

  private var titleTopConstraint: NSLayoutConstraint?
  private var titleBottomConstraint: NSLayoutConstraint?
  private var titlePageNumberLabelBottomConstraint: NSLayoutConstraint?
  private var titleLeftConstraint: NSLayoutConstraint?
  
  var leftConstraint: NSLayoutConstraint?
  
  var lastAnimationRatio: CGFloat = 0.0
  
  let sidePadding = 11.0
  var titleTopIndentL: CGFloat = Const.Size.DefaultPadding
  var titleBottomIndentL: CGFloat = -18//-18 or if subtitle set: -16*1.17-12 = -31
  let titleBottomIndentS = -4.0
  let titleTopIndentS = 2.0
    
  public var tapRecognizer = TapRecognizer()
    
  public func applyStyles() {
    titleLabel.textColor = Const.SetColor.ios(.label).color
    subTitleLabel.textColor = Const.SetColor.ios(.label).color
    pageNumberLabel.textColor = Const.SetColor.ios(.label).color
    self.backgroundColor = Const.SetColor.ios(.systemBackground).color
    line.fillColor = Const.SetColor.ios(.label).color
    line.strokeColor = Const.SetColor.ios(.label).color
  }
  
  func updateUI(){
    self.titleTopConstraint?.constant = self.titleTopIndentL
    self.layoutIfNeeded()
    self.titleBottomConstraint?.constant = titleBottomIndentL
    subTitleLabel.contentFont(size: subTitleFontSizeDefault)
    pageNumberLabel.contentFont(size: subTitleFontSizeDefault)
    lastAnimationRatio = 0.0
    titlePageNumberLabelBottomConstraint?.constant =
    (pageNumberLabel.font.pointSize - titleLabel.font.pointSize)/3
    self.subTitleLabel.alpha = 1.0
    self.line.alpha = 1.0
  }

  private var onTitleClosure: ((String?)->())?
  
  /// Define closure to call if a title has been touched
  public func onTitle(closure: @escaping (String?)->()) {
    onTitleClosure = closure
  }
  
  private func setup() {
    self.addSubview(titleLabel)
    self.addSubview(line)
    self.addSubview(subTitleLabel)
    self.addSubview(pageNumberLabel)
    
    titleLabel.adjustsFontSizeToFitWidth = true
    
    subTitleLabel.textAlignment = .right
    
    titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    line.pinHeight(DottedLineView.DottedLineDefaultHeight)
    line.backgroundColor = .clear
    line.fillColor = Const.SetColor.ios(.label).color
    line.strokeColor = Const.SetColor.ios(.label).color
    
    titleTopConstraint
    = pin(titleLabel.top, to: self.topGuide(), dist: titleTopIndentL)
    
    titleBottomConstraint
    = pin(titleLabel.bottom, to: self.bottom, dist:titleBottomIndentL)
    
    pin(subTitleLabel.bottom, to: self.bottom, dist: -5)
    
    titlePageNumberLabelBottomConstraint =
    pin(pageNumberLabel.bottom, to: titleLabel.bottom, dist: 0)
    leftConstraint = pin(pageNumberLabel.left, to: self.left, dist:8)
    
    titleLeftConstraint = pin(titleLabel.left, to: pageNumberLabel.right, dist: 8)
    pin(titleLabel.right, to: self.right, dist: -sidePadding)
    
    pin(line.left, to: self.left, dist:sidePadding)
    pin(line.right, to: self.right, dist:-sidePadding)
    pin(line.top, to: titleLabel.bottom)
    
    pin(subTitleLabel.left, to: self.left, dist:sidePadding)
    pin(subTitleLabel.right, to: self.right, dist:-sidePadding)
    borderView = self.addBorderView(.opaqueSeparator, 0.5, edge: .bottom)
    updateUI()
  }
  
  open override func layoutSubviews() {
    super.layoutSubviews()
    applyStyles()
  }

  
  public override init(frame: CGRect) {
    super.init(frame: frame)
    setup()
  }
  
  required public init?(coder: NSCoder) {
    super.init(coder: coder)
    setup()
  }
} // HeaderView

// MARK: - Scroll delegation
extension HeaderView {
  
  func scrollViewWillBeginDragging(_ offset: CGFloat) {
    beginScrollOffset = offset
  }
  
  func scrollViewDidEndDragging(_ offset: CGFloat) {
    guard let beginScrollOffset = beginScrollOffset else { return }
    didScrolling(offsetDelta: beginScrollOffset - offset, end: true)
    self.beginScrollOffset = nil
    
  }
  
  func scrollViewDidScroll(_ offset: CGFloat) {
    guard let beginScrollOffset = beginScrollOffset else { return }
    didScrolling(offsetDelta: beginScrollOffset - offset, end: false)
  }
  
  private func didScrolling(offsetDelta:CGFloat, end: Bool){
    let isMaxi = self.titleTopConstraint?.constant ?? 0.0 >= titleTopIndentL
    let isMini = self.titleTopConstraint?.constant ?? 0.0 <= titleTopIndentS
    
    if offsetDelta > 0 && isMaxi { return }
    if offsetDelta < 0 && isMini { return }
    
    switch (end, offsetDelta) {
      case (false, _)://on drag
        handleScrolling(offsetDelta: offsetDelta, animate: false)
      case (_, ..<(-maxOffset/2)):
        handleScrolling(offsetDelta: -maxOffset, animate: true)
      case (_, ..<0):
        handleScrolling(offsetDelta: maxOffset, animate: true)
      case (_, 0.0):
        break
      case (_, ..<(maxOffset/2)):
        handleScrolling(offsetDelta: -maxOffset, animate: true)
      default:
        handleScrolling(offsetDelta: maxOffset, animate: true)
    }
    if end {
      self.beginScrollOffset = nil
    }
  }
  
  func showAnimated(){
    handleScrolling(offsetDelta: maxOffset, animate: true)
  }
  
  ///negative when scroll down ...hide tf, show miniHeader
  ///positive when scroll up ...show tf, show big header
  private func handleScrolling(offsetDelta: CGFloat, animate: Bool){
    var ratio = max(0.0, min(1.0, abs(offsetDelta/maxOffset))) //0...1
    if offsetDelta > 0 { ratio = 1 - ratio }
    lastAnimationRatio = ratio
    let alpha = 1 - ratio // maxi 1...0 mini
    let fastAlpha = max(0, 1 - 2*ratio) // maxi 1...0 mini
    let titleTopIndentConst
    = alpha*(titleTopIndentL - titleTopIndentS) + titleTopIndentS
    let titleBottomIndentConst
    = alpha*(titleBottomIndentL - titleBottomIndentS) + titleBottomIndentS
    
    let titleFontSize
    = alpha*(titleFontSizeDefault - titleFontSizeMini) + titleFontSizeMini
    let labelsFontSize
    = alpha*(subTitleFontSizeDefault - subTitleFontSizeMini) + subTitleFontSizeMini
    let handler = { [weak self] in
      self?.titleLabel.titleFont(size: titleFontSize)
      self?.pageNumberLabel.contentFont(size: labelsFontSize)
      self?.subTitleLabel.contentFont(size: labelsFontSize)
      self?.titleTopConstraint?.constant = titleTopIndentConst
      self?.titleBottomConstraint?.constant = titleBottomIndentConst
      self?.subTitleLabel.alpha = fastAlpha
      self?.line.alpha = fastAlpha
    }
    animate
    ?  UIView.animate(seconds: 0.3) {  handler(); self.superview?.layoutIfNeeded() }
    : handler()
  }
}
