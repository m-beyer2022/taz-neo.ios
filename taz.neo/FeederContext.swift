//
//  FeederContext.swift
//
//  Created by Norbert Thies on 17.06.20.
//  Copyright © 2020 Norbert Thies. All rights reserved.
//

import UIKit
import NorthLib

/**
 A FeederContext manages one Feeder, its GraphQL interface to the backing
 server and its persistent data.
 
 Depending on the state of Feeder access the following Notifications are 
 sent:
   - DBReady
     when database has been initialized
   - feederReachable(FeederContext)
     network connectivity changed, feeder is reachable
   - feederUneachable(FeederContext)
     network connectivity changed, feeder is not reachable
   - feederReady(FeederContext)
     Feeder data is available (if not reachable then data is from DB)
   - feederRelease
     Feeder is going to release its data in 0.5s
   - issueOverview(Result<Issue,Error>)
     Issue Overview has been received (and stored in DB) 
   - gqlIssue(Result<GqlIssue,Error>)
     GraphQL Issue has been received (prior to "issue")
   - issue(Result<Issue,Error>), sender: Issue
     Issue with complete structural data and downloaded files is available
   - issueProgress((bytesLoaded, totalBytes))
     Issue loading progress indicator
   - resourcesReady(FeederContext)
     Resources are loaded and ready
   - resourcesProgress((bytesLoaded, totalBytes))
     Resource loading progress indicator
 */
open class FeederContext: DoesLog {
  
  /// Number of seconds to wait until we stop polling for email confirmation
  let PollTimeout: Int64 = 25*3600
  
  public var openedIssue: Issue?

  /// Name (title) of Feeder
  public var name: String
  /// Name of default Feed to show
  public var feedName: String
  /// URL of Feeder (as String)
  public var url: String
  /// Authenticator object
  public var authenticator: Authenticator! {
    didSet { setupPolling() }
  }
  /// The token for remote notifications
  public var pushToken: String?
  /// The GraphQL Feeder (from server)
  public var gqlFeeder: GqlFeeder!
  /// The stored Feeder (from DB)
  public var storedFeeder: StoredFeeder!
  /// The default Feed to show
  public var defaultFeed: StoredFeed!
  /// The Downloader to use 
  public var dloader: Downloader!
  
  
  /**
   [...]
   SCNetworkReachability and  NWPathMonitor
   is not perfect; it can result in both false positives (saying that something is reachable when it’s not) and false negatives (saying that something is unreachable when it is). It also suffers from TOCTTOU issues.
   [...]
   Source: https://developer.apple.com/forums/thread/105822
   Written by: Quinn “The Eskimo!”   Apple Developer Relations, Developer Technical Support, Core OS/Hardware
    => this is maybe the problem within our: Issue not appears, download not work issues
   */
  /// netAvailability is used to check for network access to the Feeder
  public var netAvailability: NetAvailability
  @Default("useMobile")
  public var useMobile: Bool
  
  @Default("autoloadPdf")
  var autoloadPdf: Bool
  
  @Default("simulateFailedMinVersion")
  var simulateFailedMinVersion: Bool
  
  @Default("simulateNewVersion")
  var simulateNewVersion: Bool
  
  var netStatusVerification = Date()
  
  /// isConnected returns true if the Feeder is available
  public var isConnected: Bool { 
    var isCon: Bool
    if netAvailability.isAvailable {
      if netAvailability.isMobile {
        isCon = useMobile
      } 
      else { isCon = true }
    }
    else { isCon = false }
    
    //every 60 seconds check if NetAvailability really work
    if !isCon,
       netStatusVerification.timeIntervalSinceNow < -10,
        let host = URL(string: self.url)?.host,
        NetAvailability(host: host).isAvailable {
      netStatusVerification = Date()
      log("Seams we need to update NetAvailability")
      updateNetAvailabilityObserver()
      
    }
    
    return isCon
  }
  /// Has the Feeder been initialized yet
  public var isReady = false
  
  /// Has minVersion been met?
  public var minVersionOK = true
  
  /// Bundle ID to use for App store retrieval
  public var bundleID = App.bundleIdentifier
  
  /// Overwrite for current App version
  public var currentVersion = App.version
  
  /// Server required minimal App version
  public var minVersion: Version?

  
//  public private(set) var enqueuedDownlod:[Issue] = [] {
//    didSet {
//      print("Currently Downloading: \(enqueuedDownlod.map{$0.date.gDate()})")
//    }
//  }
  
  /// Are we updating resources
  private var isUpdatingResources = false
  
  /// Are we authenticated with the server?
  public var isAuthenticated: Bool { gqlFeeder.isAuthenticated }

  /// notify sends a Notification to all objects listening to the passed
  /// String 'name'. The receiver closure gets the sending FeederContext
  /// as 'sender' argument.
  private func notify(_ name: String, content: Any? = nil) {
    Notification.send(name, content: content, sender: self)
  }
  
  /// This notify sends a Result<Type,Error>
  private func notify<Type>(_ name: String, result: Result<Type,Error>) {
    Notification.send(name, result: result, sender: self)
  }
  
  /// Present an alert indicating there is no connection to the Feeder
  public func noConnection(to: String? = nil, isExit: Bool = false,
                           closure: (()->())? = nil) {
    var sname: String? = nil
    if storedFeeder != nil { sname = storedFeeder.title }
    if let name = to ?? sname {
      let title = isExit ? "Fehler" : "Warnung"
      var msg = """
        Ich kann den \(name)-Server nicht erreichen, möglicherweise
        besteht keine Verbindung zum Internet. Oder Sie haben der App
        die Verwendung mobiler Daten nicht gestattet.
        """
      if isExit {
        msg += """
          \nBitte versuchen Sie es zu einem späteren Zeitpunkt
          noch einmal.
          """
      }
      else {
        msg += """
          \nSie können allerdings bereits heruntergeladene Ausgaben auch
          ohne Internet-Zugriff lesen.
          """        
      }
      OfflineAlert.message(title: title, message: msg, closure: closure)
    }
  }
  
  private func enforceUpdate(closure: (()->())? = nil) {
    let id = bundleID
    guard let store = try? StoreApp(id) else { 
      error("Can't find App with bundle ID '\(id)' in AppStore")
      return 
    }
    let minVersion = self.minVersion?.toString() ?? "unbekannt"
    let msg = """
      Es liegt eine neue Version dieser App mit folgenden Änderungen vor:
        
      \(store.releaseNotes)
        
      Sie haben momentan die Version \(currentVersion) installiert. Um aktuelle
      Ausgaben zu laden, ist mindestens die Version \(minVersion)
      erforderlich. Möchten Sie jetzt eine neue Version laden?
    """
    Alert.confirm(title: "Update erforderlich", message: msg) { [weak self] doUpdate in
      guard let self else { return }
      if self.simulateFailedMinVersion {
        Defaults.singleton["simulateFailedMinVersion"] = "false"
      }
      if doUpdate { 
        store.openInAppStore { closure?() }
      }
      else { exit(0) }
    }
  }
  
  private func check4Update() {
    async { [weak self] in
      guard let self else { return }
      let id = self.bundleID
      let version = self.currentVersion
      guard let store = try? StoreApp(id) else { 
        self.error("Can't find App with bundle ID '\(id)' in AppStore")
        return 
      }
      self.debug("Version check: \(version) current, \(store.version) store")
      if store.needUpdate() {
        let msg = """
        Sie haben momentan die Version \(self.currentVersion) installiert.
        Es liegt eine neue Version \(store.version) mit folgenden Änderungen vor:
        
        \(store.releaseNotes)
        
        Möchten Sie im AppStore ein Update veranlassen?
        """
        onMain(after: 2.0) { 
          Alert.confirm(title: "Update", message: msg) { [weak self] doUpdate in
            guard let self else { return }
            if self.simulateNewVersion {
              Defaults.singleton["simulateNewVersion"] = "false"
            }
            if doUpdate { store.openInAppStore() }
            else { Defaults.newStoreVersionFoundDate = Date()}///delay again for 20? days
          }
        }
      }
    }
  }
  
  /// Feeder is now reachable
  private func feederReachable(feeder: Feeder) {
    self.debug("Feeder now reachable")
    self.dloader = Downloader(feeder: feeder as! GqlFeeder)
    notify("feederReachable")
    //disables offline status label
    Notification.send("checkForNewIssues", content: StatusHeader.status.fetchNewIssues, error: nil, sender: self)
    manuelCheckForNewIssues(feed: self.defaultFeed, isAutomatically: false)
  }
  
  /// Feeder is not reachable
  private func feederUnreachable() {
    self.debug("Feeder now unreachable")
    notify("feederUneachable")
  }
  
  private func updateNetAvailabilityObserver() {
    guard let host = URL(string: self.url)?.host else {
      log("cannot update NetAvailabilityObserver for URL Host: \(url)")
      return
    }
    self.netAvailability = NetAvailability(host: host)
    self.netAvailability.onChange { [weak self] _ in self?.checkNetwork() }
  }
  
  /// Network status has changed 
  private func checkNetwork() {
    self.debug("isConnected: \(isConnected) isAuth: \(isAuthenticated)")
    if isConnected {
      //#warning("ToDo: 0.9.4 loock for logs&errors after 0.9.3 release")
      /// To discuss: idea to reset previous feeder's gqlSession's URLSession to get rid of download errors
      /// e.g. if the session exists over 3h...
      //      if let oldFeeder = self.gqlFeeder {
      //        oldFeeder.gqlSession?.session.reset {   [weak self] in
      //          self?.log("Old Session Resetted!!")
      //        }
      //      }
      
      self.gqlFeeder = GqlFeeder(title: name, url: url) { [weak self] res in
        guard let self = self else { return }
        if let feeder = res.value() {
          if let gqlFeeder = feeder as? GqlFeeder,
             let storedAuth = SimpleAuthenticator.getUserData().token {
            gqlFeeder.authToken = storedAuth
          }
          self.feederReachable(feeder: feeder)
        }
        else { self.feederUnreachable() }
      }
      ///Fix timing Bug, Demo Issue Downloaded, and probably login form shown
      if let storedAuth = SimpleAuthenticator.getUserData().token, self.gqlFeeder.authToken == nil {
        self.gqlFeeder.authToken = storedAuth
      }
    }
    else { self.feederUnreachable() }
  }
  
  /// Feeder is initialized, set up other objects
  private func feederReady() {
    self.dloader = Downloader(feeder: gqlFeeder)
    netAvailability.onChange { [weak self] _ in self?.checkNetwork() }
    defaultFeed = StoredFeed.get(name: feedName, inFeeder: storedFeeder)[0]
    isReady = true
    cleanupOldIssues()
    notify("feederReady")            
  }
  
  /// Do we need reinitialization?
  func needsReInit() -> Bool {
    if let storedFeeder = self.storedFeeder,
       let sfeed = storedFeeder.feeds.first,
       let gfeed = gqlFeeder.feeds.first {
      return !(sfeed.cycle == gfeed.cycle)
    }
    return false
  }
  
  /// React to the feeder being online or not
  private func feederStatus(isOnline: Bool) {
    debug("isOnline: \(isOnline)")
    if isOnline {
      guard minVersionOK else {
        enforceUpdate()
        return
      }
      if needsReInit() { 
        TazAppEnvironment.sharedInstance.resetApp(.cycleChangeWithLogin) 
      }
      else {
        self.storedFeeder = StoredFeeder.persist(object: self.gqlFeeder)
        feederReady()
        check4Update()
      }
    }
    else {
      let feeders = StoredFeeder.get(name: name)
      if feeders.count == 1 {
        self.storedFeeder = feeders[0]
        self.noConnection(to: name, isExit: false) {  [weak self] in
          self?.feederReady()
        }
      }
      else {
        self.noConnection(to: name, isExit: true) {   [weak self] in
          guard let self = self else { exit(0) }
          /// Try to connect if network is available now e.g. User has seen Popup No Connection
          /// User activated MobileData/WLAN, press OK => Retry not App Exit
          if self.netAvailability.isAvailable { self.connect() }
          else { exit(0) }
        }
      }
    }
  }
  
  private var pollingTimer: Timer?
  private var pollEnd: Int64?
  
  public func resume() {
    self.checkNetwork()
  }
  
  /// Start Polling if necessary
  public func setupPolling() {
    authenticator.whenPollingRequired { self.startPolling() }
    if let peStr = Defaults.singleton["pollEnd"] {
      let pe = Int64(peStr)
      if pe! <= UsTime.now.sec { endPolling() }
      else {
        pollEnd = pe
        self.pollingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, 
          repeats: true) { _ in self.doPolling() }        
      }
    }
  }
  
  /// Method called by Authenticator to start polling timer
  private func startPolling() {
    self.pollEnd = UsTime.now.sec + PollTimeout
    Defaults.singleton["pollEnd"] = "\(pollEnd!)"
    self.pollingTimer = Timer.scheduledTimer(withTimeInterval: 60.0, 
      repeats: true) { _ in self.doPolling() }
  }
  
  /// Ask Authenticator to poll server for authentication,
  /// send 
  private func doPolling() {
    authenticator.pollSubscription { [weak self] doContinue in
      guard let self = self else { return }
      guard let pollEnd = self.pollEnd else { self.endPolling(); return }
      if doContinue { if UsTime.now.sec > pollEnd { self.endPolling() } }
      else { self.endPolling() }
    }
  }
  
  /// Terminate polling
  public func endPolling() {
    self.pollingTimer?.invalidate()
    self.pollEnd = nil
    Defaults.singleton["pollEnd"] = nil
  }

  /// Ask for push token and report it to server
  public func setupRemoteNotifications(force: Bool? = false) {
    let nd = UIApplication.shared.delegate as! AppDelegate
    let dfl = Defaults.singleton
    let oldToken = dfl["pushToken"] ?? Defaults.lastKnownPushToken
    Defaults.lastKnownPushToken = oldToken
    pushToken = oldToken
    nd.onReceivePush {   [weak self] (pn, payload, _) in
      self?.processPushNotification(pn: pn, payload: payload)
    }
    nd.permitPush {[weak self] pn in
      guard let self = self else { return }
      if pn.isPermitted { 
        self.debug("Push permission granted") 
        self.pushToken = pn.deviceId
        Defaults.lastKnownPushToken = self.pushToken
      }
      else { 
        self.debug("No push permission") 
        self.pushToken = nil
      }
      dfl["pushToken"] = self.pushToken
     
      //not send request if no change and not force happens eg. on every App Start
      if force == false && oldToken == self.pushToken { return }
      // if force ensure not to send old token if oldToken == newToken
      let oldToken = (force == true && oldToken == self.pushToken) ? nil : oldToken
            
      let isTextNotification = dfl["isTextNotification"]!.bool
      
      self.gqlFeeder.notification(pushToken: self.pushToken, oldToken: oldToken,
                                  isTextNotification: isTextNotification) { [weak self] res in
        if let err = res.error() { self?.error(err) }
        else {
          Defaults.lastKnownPushToken = self?.pushToken
          self?.debug("Updated PushToken")
        }
      }
    }
  }
  
  func processPushNotification(pn: PushNotification, payload: PushNotification.Payload){
    log("Processing: \(payload)")
    switch payload.notificationType {
      case .subscription:
        log("check subscription status")
        doPolling()
      case .newIssue:
        //not using checkForNew Issues see its warning!
        //count 1 not working:
        if App.isAvailable(.AUTODOWNLOAD) == false {
          log("Currently not handle new Issue Push Current App State: \(UIApplication.shared.stateDescription)")
          return
        }
        log("Handle new Issue Push Current App State: \(UIApplication.shared.stateDescription)")
        switch UIApplication.shared.applicationState {
          case .active, .background:
            self.getOvwIssues(feed: self.defaultFeed, count: 1, isAutomatically: true)
          case .inactive:
            log("ToDo: Do inactive Download")
            self.getOvwIssues(feed: self.defaultFeed, count: 1, isAutomatically: true)
          default:
            log("Do Nothing")
        }
        
        //
      default:
        if UIApplication.shared.applicationState == .active {
          LocalNotifications.notify(payload: payload)
        }
        self.debug(payload.toString())
    }
  }
  
  /// Request authentication from Authenticator
  /// Authenticator will send Const.NotificationNames.authenticationSucceeded Notification if successful
  public func authenticate() {
    authenticator.authenticate(with: nil)
  }
  
  public func updateAuthIfNeeded() {
    //self.isAuthenticated == false
    if let storedAuth = SimpleAuthenticator.getUserData().token,
       ( self.gqlFeeder.authToken == nil || self.gqlFeeder.authToken != storedAuth )
    {
      self.gqlFeeder.authToken = storedAuth
    }
  }
  
  /// Connect to Feeder and send "feederReady" Notification
  private func connect() {
    gqlFeeder = GqlFeeder(title: name, url: url) { [weak self] res in
      guard let self else { return }
      if let _ = res.value() {
        if self.simulateFailedMinVersion {
          self.minVersion = Version("135.0.0")
          self.minVersionOK = false
        }
        else { self.minVersionOK = true }
        self.feederStatus(isOnline: true)
      }
      else {
        if let err = res.error() as? FeederError {
          if case .minVersionRequired(let smv) = err {
            self.minVersion = Version(smv)
            self.debug("App Min Version \(smv) failed")
            self.minVersionOK = false
          }
          else { self.minVersionOK = true }
        }
        self.feederStatus(isOnline: false)
      }
    }
    authenticator = DefaultAuthenticator(feeder: gqlFeeder)
  }

  /// openDB opens the Article database and sends a "DBReady" notification  
  private func openDB(name: String) {
    guard ArticleDB.singleton == nil else { return }
    ArticleDB(name: name) { [weak self] _ in
      self?.notify("DBReady") 
    }
  }
  
  /// closeDB closes the Article database
  private func closeDB() {
    if let db = ArticleDB.singleton {
      db.close()
      ArticleDB.singleton = nil
    }
  }
  
  /// resetDB removes the Article database and uses openDB to reopen a new version
  private func resetDB() {
    guard ArticleDB.singleton != nil else { return }
    let name = ArticleDB.singleton.name
    closeDB()
    ArticleDB.dbRemove(name: name)
    openDB(name: name)
  }
    
  /// init sends a "feederReady" Notification when the feeder context has
  /// been set up
  public init?(name: String, url: String, feed feedName: String) {
    guard let host = URL(string: url)?.host else { return nil }
    self.name = name
    self.url = url
    self.feedName = feedName
    self.netAvailability = NetAvailability(host: host)
    if self.simulateNewVersion || simulateFailedMinVersion {
      self.bundleID = "de.taz.taz.2"
    }
    if self.simulateNewVersion {
      self.currentVersion = Version("0.5.0")      
    }
    Notification.receive("DBReady") { [weak self] _ in
      self?.debug("DB Ready")
      self?.connect()
    }
    Notification.receive(UIApplication.willEnterForegroundNotification) { [weak self] _ in
      guard let self else { return }
      if !self.minVersionOK { 
        onMain(after: 1.0) {
          self.log("Exit due to minimal version not met")
          exit(0)
        }
      }
    }
    openDB(name: name)
  }
  
  /// release closes the Database and removes all feeder specific content
  /// if isRemove == true. Also all other resources are released.
  public func release(isRemove: Bool, onRelease: @escaping ()->()) {
    notify("feederRelease")
    onMain(after: 0.5) { [weak self] in
      guard let self else { return }
      let feederDir = self.gqlFeeder?.dir
      self.gqlFeeder?.release()
      self.gqlFeeder = nil
      self.dloader?.release()
      self.dloader = nil
      self.closeDB()
      if let dir = feederDir, isRemove {
        for f in dir.scan() { File(f).remove() }
      }
      onRelease()
    }
  }
  
  private func loadBundledResources(setVersion: Int? = nil) {
    if case let bundledResources = BundledResources(),
            let result = bundledResources.resourcesPayload.value(),
            let res = result["resources"],
            bundledResources.bundledFiles.count > 0 {
      if let v = setVersion { res.resourceVersion = v }
      let success = persistBundledResources(bundledResources: bundledResources,
                                             resData: res)
      if success == true {
        ArticleDB.save()
        log("Bundled Resources version \(res.resourceVersion) successfully loaded")
      }
    }
  }
  
  /// Load resources from server with optional cache directory
  private func loadResources(res: Resources, fromCacheDir: String? = nil) {
    let previous = StoredResources.latest()
    let resources = StoredResources.persist(object: res)
    self.dloader.createDirs()
    var onProgress: ((Int64,Int64)->())? = { (bytesLoaded,totalBytes) in
      self.notify("resourcesProgress", content: (bytesLoaded,totalBytes))
    }
    if fromCacheDir != nil { onProgress = nil }
    resources.isDownloading = true
    self.dloader.downloadPayload(payload: resources.payload as! StoredPayload,
                                 fromCacheDir: fromCacheDir,
                                 onProgress: onProgress) { err in
      resources.isDownloading = false
      if err == nil {
        let source: String = fromCacheDir ?? "server"
        self.debug("Resources version \(resources.resourceVersion) loaded from \(source)")
        self.notify("resourcesReady")
        /// Delete unneeded old resources
        if let prev = previous, prev.resourceVersion < resources.resourceVersion {
          prev.delete()
        }
        ArticleDB.save()
      }
      self.isUpdatingResources = false
    }
  }
  
  /// Downloads resources if necessary
  public func updateResources(toVersion: Int = -1) {
    guard !isUpdatingResources else { return }
    isUpdatingResources = true
    let version = (toVersion < 0) ? storedFeeder.resourceVersion : toVersion
    if StoredResources.latest() == nil { loadBundledResources(/*setVersion: 1*/) }
    if let latest = StoredResources.latest() {
      if latest.resourceVersion >= version, latest.isComplete {
        isUpdatingResources = false
        debug("No need to read resources version \(latest.resourceVersion)")
        notify("resourcesReady");
        return
      }
    }
    if !isConnected {
      //Skip Offline Start Deathlock //TODO TEST either notify("resourcesReady"); or:
      isUpdatingResources = false
      noConnection()
      return
    }
    // update from server needed
    gqlFeeder.resources { [weak self] result in
      guard let self = self, let res = result.value() else { return }
      self.loadResources(res: res)
    }
  }
  
  /// persist helper function for updateResources
  /// - Parameters:
  ///   - bundledResources: the resources (with files) to persist
  ///   - resData: the GqlResources data object to persist
  /// - Returns: true if succeed
  private func persistBundledResources(bundledResources: BundledResources,
                                        resData : GqlResources) -> Bool {
    //Use Bundled Resources!
    resData.setPayload(feeder: self.gqlFeeder)
    let resources = StoredResources.persist(object: resData)
    self.dloader.createDirs()
    resources.isDownloading = true
    var success = true
    
    if bundledResources.bundledFiles.count != resData.files.count {
      log("WARNING: Something is Wrong maybe need to download additional Files!")
      success = false
    }
    
    var bundledResourceFiles : [File] = []
    
    for fileUrl in bundledResources.bundledFiles {
      let file = File(fileUrl)
      if file.exists {
        bundledResourceFiles.append(file)
      }
    }
    
    let globalFiles = resources.payload.files.filter {
      $0.storageType != .global
    }
    
    for globalFile in globalFiles {
      let bundledFiles = bundledResourceFiles.filter{ $0.basename == globalFile.name }
      if bundledFiles.count > 1 { log("Warning found multiple matching Files!")}
      guard let bundledFile = bundledFiles.first else {
        log("Warning not found matching File!")
        success = false
        continue
      }
      
      /// File Creation Dates did not Match! bundledFile.mTime != globalFile.moTime
      if bundledFile.exists,
         bundledFile.size == globalFile.size {
        let targetPath = self.gqlFeeder.resourcesDir.path + "/" + globalFile.name
        bundledFile.copy(to: targetPath)
        let destFile = File(targetPath)
        if destFile.exists { destFile.mTime = globalFile.moTime }
        debug("File \(bundledFile.basename) moved... exist in resdir? : \(globalFile.existsIgnoringTime(inDir: self.gqlFeeder.resourcesDir.path))")
      } else {
        log("* Warning: File \(bundledFile.basename) may not exist (\(bundledFile.exists)), mtime, size is wrong  \(bundledFile.size) !=? \(globalFile.size)")
        success = false
      }
    }
    resources.isDownloading = false
    if success == false {
      log("* Warning: There was an error due persisting Bundled Ressources ....delete them.")
      resources.delete()
    }
    return success
  }
  
  func updateSubscriptionStatus(closure: @escaping (Bool)->()) {
    self.gqlFeeder.customerInfo { [weak self] res in
      switch res {
      case .success(let ci):
          Defaults.customerType = ci.customerType
          closure(true)
      case .failure(let err):
          self?.log("cannot get customerInfo: \(err)")
          closure(false)
      }
    }
  }
  
  func clearExpiredAccountFeederError(){
    if currentFeederErrorReason == .expiredAccount(nil) {
      currentFeederErrorReason = nil
    }
  }
  
  var currentFeederErrorReason : FeederError?
  
  /// Feeder has flagged an error
  func handleFeederError(_ err: FeederError, closure: @escaping ()->()) {
    //prevent multiple appeariance of the same alert
    if let curr = currentFeederErrorReason, curr === err {
      ///not refactor and add closures to alert cause in case of later changes/programming errors may
      ///lot of similar closure calls added and may result in other errors e.g. multiple times of calling getOwvIssue...
      log("Closure not added"); return
    }
    debug("handleFeederError for: \(err)")
    currentFeederErrorReason = err
    var text = ""
    switch err {
      case .expiredAccount: text = "Ihr Abonnement ist am \(err.expiredAccountDate?.gDate() ?? "-") abgelaufen.\nSie können bereits heruntergeladene Ausgaben weiterhin lesen.\n\nUm auf weitere Ausgaben zuzugreifen melden Sie sich bitte mit einem aktiven Abo an. Für Fragen zu Ihrem Abonnement kontaktieren Sie bitte unseren Service via: digiabo@taz.de."
        if Defaults.expiredAccountDate != nil {
          closure()
          return //dont show popup on each start
        }
        if Defaults.expiredAccountDate == nil {
          Defaults.expiredAccountDate =  err.expiredAccountDate ?? Date()
        }
        updateSubscriptionStatus { _ in
          self.authenticator.authenticate(with: nil)
        }
        closure()
        return; //Prevent default Popup
      case .invalidAccount: text = "Ihre Kundendaten sind nicht korrekt."
        fallthrough
      case .changedAccount: text = "Ihre Kundendaten haben sich geändert.\n\nSie wurden abgemeldet. Bitte melden Sie sich erneut an!"
        TazAppEnvironment.sharedInstance.deleteUserData(logoutFromServer: true)
      case .unexpectedResponse:
        Alert.message(title: "Fehler",
                      message: "Es gab ein Problem bei der Kommunikation mit dem Server") {
          exit(0)
        }
      case.minVersionRequired: break
    }
    Alert.message(title: "Fehler", message: text, additionalActions: nil,  closure: { [weak self] in
      ///Do not authenticate here because its not needed here e.g.
      /// expired account due probeabo, user may not want to auth again
      /// additionally it makes more problems currently e.g. Overlay may appear and not disappear
      self?.currentFeederErrorReason = nil
      closure()
    })
  }
  
  public func getStoredOvwIssues(feed: Feed, count: Int = 10){
    let sfs = StoredFeed.get(name: feed.name, inFeeder: storedFeeder)
    if let sf0 = sfs.first {
      let sissues = StoredIssue.issuesInFeed(feed: sf0, count: 10)
      for issue in sissues {
        if issue.isOvwComplete {
          self.notify("issueOverview", result: .success(issue))
        }
      }
    }
  }
  
  /**
   Get Overview Issues from Feed
   
   If we are online, 'count' Issue overviews are requested from the server.
   Otherwise 'count' Issues from the DB are returned. The returned Issues are always 
   StoredIssues.
   */
  public func getOvwIssues(feed: Feed, count: Int, fromDate: Date? = nil, isAutomatically: Bool) {
    log("feed: \(feed.name) count: \(count) fromDate: \(fromDate?.short ?? "-")")
    let sfs = StoredFeed.get(name: feed.name, inFeeder: storedFeeder)
    guard sfs.count > 0 else { return }
    let sfeed = sfs[0]
    let sicount = sfeed.issues?.count ?? 0
    guard sicount < sfeed.issueCnt else { return }
    Notification.receiveOnce("resourcesReady") { [weak self] err in
      guard let self = self else { return }
      if self.isConnected {
        self.gqlFeeder.issues(feed: sfeed, date: fromDate, count: min(count, 20),
                              isOverview: true) { res in
          if let issues = res.value() {
            for issue in issues {
              let si = StoredIssue.get(date: issue.date, inFeed: sfeed)
              if si.count < 1 { StoredIssue.persist(object: issue) }
              //#warning("ToDo 0.9.4+: Missing Update of an stored Issue")
              ///in old app timestamps are compared!
              ///What if Overview new MoTime but compleete Issue is in DB and User is in Issue to read!!
              /// if si.first?.moTime != issue.moTime ...
              /// an update may result in a crash
            }
            ArticleDB.save()
            let sissues = StoredIssue.issuesInFeed(feed: sfeed, count: count, 
                                                   fromDate: fromDate)
            for issue in sissues { self.downloadIssue(issue: issue, isAutomatically: isAutomatically) }
          }
          else {
            if let err = res.error() as? FeederError {
              self.handleFeederError(err) { 
                self.getOvwIssues(feed: feed, count: count, fromDate: fromDate, isAutomatically: isAutomatically)
              }
            }
            else { 
              let res: Result<Issue,Error> = .failure(res.error()!)
              self.notify("issueOverview", result: res)
            }
            return
          }
        }
      }
      else {
        let sissues = StoredIssue.issuesInFeed(feed: sfeed, count: count, 
                                               fromDate: fromDate)
        for issue in sissues {
          if issue.isOvwComplete {
            self.notify("issueOverview", result: .success(issue))
          }
          else {
            self.downloadIssue(issue: issue, isAutomatically: isAutomatically)
          }
        }
      }
    }
    updateResources()
  }

  #warning("2 more things: ")
  ///2 sachen on re enter app if last check > 60s && last Issue > 4h => do manuell check
  ///
  ///
  /// checkForNewIssues requests new overview issues from the server if
  /// more than 12 hours have passed since the latest stored issue
  public func manuelCheckForNewIssues(feed: Feed, isAutomatically: Bool) {
    let sfs = StoredFeed.get(name: feed.name, inFeeder: storedFeeder)
    guard sfs.count > 0 else { return }
    let sfeed = sfs[0]
    if let latest = StoredIssue.latest(feed: sfeed), self.isConnected {
      let now = UsTime.now
      let latestIssueDate = UsTime(latest.date) //UsTime(year: 2023, month: 3, day: 23, hour: 3, min: 0, sec: 0) ??
      let ndays = max(2, (now.sec - latestIssueDate.sec) / (3600*24) + 1)//ensure to load at least 2 current issue previews
      getOvwIssues(feed: feed, count: Int(ndays), isAutomatically: isAutomatically)
    }
    else if self.isConnected == false {
      Notification.send("checkForNewIssues", content: StatusHeader.status.offline, error: nil, sender: self)
    }
    else {
      Notification.send("checkForNewIssues", content: StatusHeader.status.none, error: nil, sender: self)
    }
  }

  /// Returns true if the Issue needs to be updated
  public func needsUpdate(issue: Issue) -> Bool {
    guard !issue.isDownloading else { return false }
    
    if issue.isComplete, issue.isReduced, isAuthenticated, !Defaults.expiredAccount {
      issue.isComplete = false
    }
    return !issue.isComplete
  }
  
  
  public func needsUpdate(issue: Issue, toShowPdf: Bool = false) -> Bool {
    var needsUpdate = needsUpdate(issue: issue)
    if needsUpdate == false && toShowPdf == true {
      needsUpdate = !issue.isCompleetePDF(in: gqlFeeder.issueDir(issue: issue))
    }
    return needsUpdate
  }
  
  /**
   Get an Issue from Server or local DB
   
   This method retrieves a complete Issue (ie downloaded Issue with complete structural
   data) from the database. If necessary all files are downloaded from the server.
   */
  public func getCompleteIssue(issue: StoredIssue, isPages: Bool = false, isAutomatically: Bool) {
    self.debug("isConnected: \(isConnected) isAuth: \(isAuthenticated) issueDate:  \(issue.date.short)")
    if issue.isDownloading {
      Notification.receiveOnce("issue", from: issue) { [weak self] notif in
        self?.getCompleteIssue(issue: issue, isPages: isPages, isAutomatically: isAutomatically)
      }
      return
    }
    let loadPages = isPages || autoloadPdf
    guard needsUpdate(issue: issue, toShowPdf: loadPages) else {
      Notification.send("issue", result: .success(issue), sender: issue)
      return      
    }
    if self.isConnected {
      gqlFeeder.issues(feed: issue.feed, date: issue.date, count: 1,
                       isPages: loadPages) { res in
        if let issues = res.value(), issues.count == 1 {
          let dissue = issues[0]
          Notification.send("gqlIssue", result: .success(dissue), sender: issue)
          if issue.date != dissue.date {
            self.error("Cannot Update issue \(issue.date.short)/\(issue.isWeekend ? "weekend" : "weekday") with issue \(dissue.date.short)/\(dissue.isWeekend ? "weekend" : "weekday") feeders cycle: \(self.gqlFeeder.feeds.first?.cycle.toString() ?? "-")")
            let unexpectedResult : Result<[Issue], Error>
              = .failure(DownloadError(message: "Weekend Login cannot load weekday issues", handled: true))
            Notification.send("issueStructure", result: unexpectedResult, sender: issue)
            TazAppEnvironment.sharedInstance.resetApp(.wrongCycleDownloadError)
            return
          }
          issue.update(from: dissue)
          ArticleDB.save()
          Notification.send("issueStructure", result: .success(issue), sender: issue)
          self.downloadIssue(issue: issue, isComplete: true, isAutomatically: isAutomatically)
        }
        else if let err = res.error() {
          let errorResult : Result<[Issue], Error>
            = .failure(DownloadError(handled: false, enclosedError: err))
          Notification.send("issueStructure",
                            result: errorResult,
                            sender: issue)
        }
        else {
          //prevent ui deadlock
          let unexpectedResult : Result<[Issue], Error>
            = .failure(DownloadError(message: "Unexpected Behaviour", handled: false))
          Notification.send("issueStructure", result: unexpectedResult, sender: issue)
        }
      }
    }
    else {
      noConnection();
      let res : Result<Any, Error>
        = .failure(DownloadError(message: "no connection", handled: true))
      Notification.send("issueStructure", result: res, sender: issue)
    }
  }
  
  /// Tell server we are starting to download
  func markStartDownload(feed: Feed, issue: Issue, isAutomatically: Bool, closure: @escaping (String?, UsTime)->()) {
    let isPush = pushToken != nil
    debug("Sending start of download to server")
    self.gqlFeeder.startDownload(feed: feed, issue: issue, isPush: isPush, pushToken: self.pushToken, isAutomatically: isAutomatically) { res in
      closure(res.value(), UsTime.now)
    }
  }
  
  /// Tell server we stopped downloading
  func markStopDownload(dlId: String?, tstart: UsTime) {
    if let dlId = dlId {
      let nsec = UsTime.now.timeInterval - tstart.timeInterval
      debug("Sending stop of download to server")
      self.gqlFeeder.stopDownload(dlId: dlId, seconds: nsec){_ in}
    }
  }
  
  func didDownload(_ issue: Issue){
    guard issue.date == self.defaultFeed.lastIssue else { return }
    guard let momentPublicationDate = issue.moment.files.first?.moTime else { return }
    ///momentPublicationDate is in UTC timeIntervalSinceNow calculates also with utc, so timeZone calculation needed!
    //is called multiple times!
    //debug("New Issue:\n  issue Date: \(issue.date)\n  defaultFeed.lastIssue: \(self.defaultFeed.lastIssue)\n  defaultFeed.lastUpdated: \(self.defaultFeed.lastUpdated)\n  defaultFeed.lastIssueRead: \(self.defaultFeed.lastIssueRead)")
    NotificationBusiness
      .sharedInstance
      .showPopupIfNeeded(newIssueAvailableSince: -momentPublicationDate.timeIntervalSinceNow)
    
  }
  
  func cleanupOldIssues(){
    if self.dloader.isDownloading { return }
    guard let feed = self.storedFeeder.feeds[0] as? StoredFeed else { return }
    let persistedIssuesCount:Int = Defaults.singleton["persistedIssuesCount"]?.int ?? 20
    StoredIssue.removeOldest(feed: feed,
                             keepDownloaded: persistedIssuesCount,
                             deleteOrphanFolders: true)
  }
  
  /// Download partial Payload of Issue
  private func downloadPartialIssue(issue: StoredIssue) {
    self.debug("isConnected: \(isConnected) isAuth: \(isAuthenticated) issueDate: \(issue.date.short)")
    self.dloader.downloadPayload(payload: issue.payload as! StoredPayload, atEnd: { [weak self] err in
      var res: Result<StoredIssue,Error>
      if err == nil {
        issue.isOvwComplete = true
        res = .success(issue)
        ArticleDB.save()
        self?.didDownload(issue)
      }
      else { res = .failure(err!) }
      Notification.send("issueOverview", result: res, sender: issue)
    })
  }

  /// Download complete Payload of Issue
  private func downloadCompleteIssue(issue: StoredIssue, isAutomatically: Bool) {
//    enqueuedDownlod.append(issue)
    self.debug("isConnected: \(isConnected) isAuth: \(isAuthenticated)")
    markStartDownload(feed: issue.feed, issue: issue, isAutomatically: isAutomatically) { (dlId, tstart) in
      issue.isDownloading = true
      self.dloader.downloadPayload(payload: issue.payload as! StoredPayload, 
        onProgress: { (bytesLoaded,totalBytes) in
          Notification.send("issueProgress", content: (bytesLoaded,totalBytes),
                            sender: issue)
        }) {[weak self] err in
        issue.isDownloading = false
        var res: Result<StoredIssue,Error>
        if err == nil { 
          res = .success(issue) 
          issue.isComplete = true
          ArticleDB.save()
          self?.didDownload(issue)
          //inform DownloadStatusButton: download finished
          Notification.send("issueProgress", content: (1,1), sender: issue)
        }
        else { res = .failure(err!) }
        self?.markStopDownload(dlId: dlId, tstart: tstart)
//        self.enqueuedDownlod.removeAll{ $0.date == issue.date}
        Notification.send("issue", result: res, sender: issue)
      }
    }
  }
  
  /// Download Issue files and resources if necessary
  private func downloadIssue(issue: StoredIssue, isComplete: Bool = false, isAutomatically: Bool) {
    self.debug("isConnected: \(isConnected) isAuth: \(isAuthenticated)\(Defaults.expiredAccount ? " Expired!" : "") isComplete: \(isComplete) issueDate: \(issue.date.short)")
    Notification.receiveOnce("resourcesReady") { [weak self] err in
      guard let self = self else { return }
      self.dloader.createIssueDir(issue: issue)
      if self.isConnected { 
        if isComplete { self.downloadCompleteIssue(issue: issue, isAutomatically: isAutomatically) }
        else { self.downloadPartialIssue(issue: issue) }
      }
      else { self.noConnection() }
    }
    updateResources(toVersion: issue.minResourceVersion)
  }

} // FeederContext


extension PushNotification.Payload {
  public var notificationType: NotificationType? {
    get {
      guard let data = self.custom["data"] as? [AnyHashable:Any] else { return nil }
      for case let (key, value) as (String, String) in data {
        if key == "perform" && value == "subscriptionPoll" {
          return NotificationType.subscription
        }
        else if key == "refresh" && value == "aboPoll" {
          return NotificationType.newIssue
        }
      }
      return nil
    }
  }
}

fileprivate extension LocalNotifications {
  static func notify(payload: PushNotification.Payload){
    guard let message = payload.standard?.alert?.body else {
      Log.debug("no standard payload found, not notify localy")
      return
    }
    Self.notify(title: payload.standard?.alert?.title, message:message)
  }
}


fileprivate extension StoreApp {
  
  ///check if App Update Popup should be shown
  func needUpdate() -> Bool {
    ///ensure store version is higher then running version
    guard self.version > App.version else { return false }
    
    ///ensure store version is the same like the delayed one otherwise delay the store version
    ///to e.g. current version 0.20.0 delayed 0.20.1 has critical bug 0.20.2 is in phased release
    ///ensure not all 0.20.0 users get 0.20.2, they should stay on 0.20.0 for a while
    guard let delayedVersion = Defaults.singleton["newStoreVersion"],
          delayedVersion == self.version.toString() else {
      Defaults.singleton["newStoreVersion"] = self.version.toString()
      Defaults.newStoreVersionFoundDate = Date()
      return false
    }
    
    ///ensure update popup for **NON AUTOMATIC UPDATE USERS only** comes et first after
    /// x days 20 = 60s*60min*24h*20d* = 3600*24*20  ::: Test 2 Minutes == 60*2*
    guard let versionFoundDate = Defaults.newStoreVersionFoundDate,
          abs(versionFoundDate.timeIntervalSinceNow) > 3600*24*20 else {
      return false
    }
    ///update is needed
    return true
  }
}

fileprivate extension Defaults {
  
  ///Helper to persist newStoreVersionFoundDate
  ///no need to reset on reset App, no need to use somewhere else
  static var newStoreVersionFoundDate : Date? {
    get {
      if let curr = Defaults.singleton["newStoreVersionFoundDate"] {
        return Date.fromString(curr)
      }
      return nil
    }
    set {
      if let date = newValue {
        Defaults.singleton["newStoreVersionFoundDate"] = Date.toString(date)
      }
      else {
        Defaults.singleton["newStoreVersionFoundDate"] = nil
      }
    }
  }
}
