//
//  ITVScrollView.swift
//  Pods
//
//  Created by Jakub Fiser on 13/10/2016.
//
//

import UIKit

/// Enum of supported image apis.
public enum ITVImageAPI {
    /// IIIF Image API
    case IIIF
    /// Zoomify API
    case Zoomify
    /// Some other API
    case Unknown
}

/**
 The main class of the iOSTiledViewer library. All communication is done throught this class. See example project to see how to set correctly the class. It has to be initialized through storyboard.
 Assign ITVErrorDelegate to receive errors related to displaying images. The assignment should be done before calling `loadImage(_:)` or `loadImage(_:api:)` method to ensure you receive all errors. Test link: `ITVScrollView.itvDelegate`
 */
open class ITVScrollView: UIScrollView {
    
    /// Delegate for receiving errors and some important events.
    public var itvDelegate: ITVScrollViewDelegate? {
        didSet {
            containerView.itvDelegate = itvDelegate
        }
    }
    
    /// Returns true only if content is not scaled.
    public var isZoomedOut: Bool {
        return self.zoomScale <= self.minimumZoomScale
    }
    
    /// Returns an array of possible image formats as Strings.
    public var imageFormats: [String]? {
        return containerView.image?.formats
    }
    
    /// Returns and sets current image format
    public var currentFormat: String? {
        get {
            return containerView.image?.format
        }
        set {
            containerView.image?.format = newValue
            containerView.loadBackground()
            containerView.clearCache()
            containerView.refreshTiles()
        }
    }
    
    /// Returns an array of possible image qualities as Strings.
    public var imageQualities: [String]? {
        return containerView.image?.qualities
    }
    
    /// Returns and sets current image quality
    public var currentQuality: String? {
        get {
            return containerView.image?.quality
        }
        set {
            containerView.image?.quality = newValue
            containerView.loadBackground()
            containerView.clearCache()
            containerView.refreshTiles()
        }
    }
    
    /// Returns array of possible zoom scales.
    public var zoomScales: [CGFloat] {
        return containerView.image != nil ? containerView.image!.zoomScales : [1]
    }
    
    open override var bounds: CGRect {
        didSet {
            // update scales when bounds change
            if let img = containerView.image {
                recomputeSize(image: img)
            }
        }
    }
    
    fileprivate let containerView = ITVContainerView()
    fileprivate let licenseView = ITVLicenceView()
    fileprivate var lastLevel: Int = -1
    fileprivate var minBounceScale: CGFloat = 0
    fileprivate var maxBounceScale: CGFloat = 0
    
    fileprivate var url: String? {
        didSet {
            if url != nil {
                // clear previous image's information
                initVariables()
                
                var block: ((Data?, URLResponse?, Error?) -> Void)? = nil
                if url!.contains(IIIFImageDescriptor.propertyFile) {
                    // IIIF
                    block = {(data, response, error) in
                        let code = (response as? HTTPURLResponse)?.statusCode
                        if code == 200, data != nil , let serialization = try? JSONSerialization.jsonObject(with: data!, options: .allowFragments) {
                            
                            let imageDescriptor = IIIFImageDescriptor.versionedDescriptor(serialization as! [String : Any])
                            DispatchQueue.main.async {
                                self.initWithDescriptor(imageDescriptor)
                            }
                        } else {
                            let error = NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY:"Error loading IIIF image information."])
                            DispatchQueue.main.async {
                                self.itvDelegate?.didFinishLoading(error: error)
                            }
                        }
                    }
                }
                else if url!.contains(ZoomifyImageDescriptor.propertyFile) {
                    // Zoomify
                    block = {(data, response, error) in
                        let code = (response as? HTTPURLResponse)?.statusCode
                        if code == 200, data != nil , let json = SynchronousZoomifyXMLParser().parse(data!) {
                            
                            let imageDescriptor = ZoomifyImageDescriptor(json, self.url!)
                            DispatchQueue.main.async {
                                self.initWithDescriptor(imageDescriptor)
                            }
                        } else {
                            let error = NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY:"Error loading Zoomify image information."])
                            DispatchQueue.main.async {
                                self.itvDelegate?.didFinishLoading(error: error)
                            }
                        }
                    }
                }
                
                guard block != nil else {
                    // unsupported image API, should never happen here
                    let error = NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY:"Unsupported image API."])
                    itvDelegate?.didFinishLoading(error: error)
                    return
                }
                
                URLSession.shared.dataTask(with: URL(string: url!)!, completionHandler:
                        block!).resume()
            }
        }
    }
    
    override open func awakeFromNib() {
        super.awakeFromNib()
        
        // set scroll view delegate
        delegate = self
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        
        // add container view with tiled and background views
        addSubview(containerView)
        containerView.initTiledView()
        
        // add license view
        superview?.addSubview(licenseView)
        licenseView.translatesAutoresizingMaskIntoConstraints = false
        superview?.addConstraints([
            NSLayoutConstraint(item: self, attribute: .trailing, relatedBy: .equal, toItem: licenseView, attribute: .trailing, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .bottom, relatedBy: .equal, toItem: licenseView, attribute: .bottom, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .leading, relatedBy: .lessThanOrEqual, toItem: licenseView, attribute: .leading, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: self, attribute: .top, relatedBy: .lessThanOrEqual, toItem: licenseView, attribute: .top, multiplier: 1.0, constant: 0)
            ])
        
        // add double tap to zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(ITVScrollView.didTap))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }
    
    /**
     Call this method to rotate an image.
     
     - parameter angle: Number in range <-360, 360>
     - note: Rotation has not been implemented yet.
     */
    public func rotateImage(angle: CGFloat) {
        guard case -360...360 = angle else {
            print("Invalid rotation with angle: \(angle).")
            return
        }
        print("Rotate function has not been implemented yet.")
    }
    
    /**
     Method for loading image.
     
     - parameter imageUrl: URL of image to load.
     - parameter api: Specify image api. Currently can be of values IIIF, Zoomify and Unknown.
     */
    public func loadImage(_ imageUrl: String, api: ITVImageAPI) {
        switch api {
            case .IIIF:
                if !imageUrl.contains(IIIFImageDescriptor.propertyFile) {
                    url = imageUrl + (imageUrl.characters.last != "/" ? "/" : "") + IIIFImageDescriptor.propertyFile
                }
                else {
                    url = imageUrl
                }
                
            case .Zoomify:
                if !imageUrl.contains(ZoomifyImageDescriptor.propertyFile) {
                    url = imageUrl + (imageUrl.characters.last != "/" ? "/" : "") + ZoomifyImageDescriptor.propertyFile
                }
                else {
                    url = imageUrl
                }
            
            case .Unknown:
                loadImage(imageUrl)
        }
    }
    
    /**
     Method for zooming.
     
     - parameter scale: Scale to zoom.
     - parameter animated: Animation flag.
     */
    public func zoomToScale(_ scale: CGFloat, animated: Bool) {
        setZoomScale(scale, animated: animated)
    }
    
    /// Method for releasing cached images when device runs low on memory. Should be called by UIViewController when needed.
    public func didRecieveMemoryWarning() {
        containerView.clearCache()
    }
    
    /// Use to immediately refresh layout
    public func refreshTiles() {
        containerView.refreshTiles()
    }
    
    fileprivate var lastZoomScale: CGFloat = 0
    fileprivate var doubleTapToZoom = true
    // Listener on double tap gesture that changes zoom accordingly:
    // - if last zoom was equal to minimal zoom, then zoom will be increased
    // - if last zoom was equal to maximal zoom, then zoom will be necreased
    // - if last zoom was in, then zoom will be increased
    // - if last zoom was out, then zoom will be decreased
    public func didTap() {
        let level = lastLevel + (doubleTapToZoom ? 1 : -1)
        zoomToScale(pow(2.0, CGFloat(level)), animated: true)
    }
}

fileprivate extension ITVScrollView {
    
    // Reinitialize all important variables to their defaults
    fileprivate func initVariables() {
        // reset double tap to zoom variables
        lastZoomScale = 0
        doubleTapToZoom = true
        
        // reset bouncing
        minBounceScale = 0.2
        maxBounceScale = 1.8
        
        // default scale
        lastLevel = -1
        minimumZoomScale = 1.0
        maximumZoomScale = 1.0
        zoomScale = minimumZoomScale
        
        // clear container view
        containerView.clearViews()
        containerView.frame = CGRect(origin: CGPoint.zero, size: frame.size)
    }
    
    // Resizing tiled view to fit in scroll view
    fileprivate func resizeTiledView(image: ITVImageDescriptor) {
        var newSize = image.sizeToFit(size: frame.size)
        containerView.frame = CGRect(origin: CGPoint.zero, size: newSize)
        scrollViewDidZoom(self)
    }
    
    // Recompute scales by actual frame size and set minimumZoomScale
    fileprivate func recomputeSize(image: ITVImageDescriptor) {
        guard !isZooming, !isZoomBouncing else {
            return
        }
        
        image.adjustToFit(size: frame.size)
        let wasZoomedOut = isZoomedOut
        setScaleLimits(image: image)
        if wasZoomedOut {
            zoomScale = minimumZoomScale
        }
        
        scrollViewDidZoom(self)
    }
    
    fileprivate func setScaleLimits(image: ITVImageDescriptor) {
        let scales = image.zoomScales
        maximumZoomScale = scales.max()!
        minimumZoomScale = scales.min()!
        
        let minLevel = Int(round(log2(minimumZoomScale)))
        let maxLevel = Int(round(log2(maximumZoomScale)))
        minBounceScale = pow(2.0, CGFloat(minLevel - 1)) + 0.2
        maxBounceScale = pow(2.0, CGFloat(maxLevel + 1)) - 0.2
    }
    
    // Initializing tiled view and scroll view's zooming
    fileprivate func initWithDescriptor(_ imageDescriptor: ITVImageDescriptor?) {
        guard var image = imageDescriptor, image.error == nil else {
            let error = imageDescriptor?.error != nil ? imageDescriptor!.error! : NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY:"Error getting image information."])
            itvDelegate?.didFinishLoading(error: error)
            return
        }
        
        resizeTiledView(image: image)
        setScaleLimits(image: image)
        zoomScale = minimumZoomScale
        changeLevel(forScale: minimumZoomScale)
        containerView.image = image
        licenseView.imageDescriptor = image
        
        itvDelegate?.didFinishLoading(error: nil)
    }
    
    // Synchronous test for url content download
    fileprivate func testUrlContent(_ stringUrl: String) -> Bool {
        guard let url = URL(string: stringUrl) else {
            return false
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
            if (response as? HTTPURLResponse)?.statusCode == 200 {
                result = true
            }
            semaphore.signal()
        }).resume()
        
        semaphore.wait()
        return result
    }
    
    fileprivate func changeLevel(forScale scale: CGFloat) {
        // redraw image by setting contentScaleFactor on tiledView
        let level = Int(round(log2(scale)))
        if level != lastLevel {
            containerView.tiledView.contentScaleFactor = pow(2.0, CGFloat(level))
            lastLevel = level
        }
    }

    /**
     Method for loading image.
     - parameter imageUrl: URL of image to load. Currently only IIIF and Zoomify images are supported. For IIIF images, pass in URL to property file or containing "/full/full/0/default.jpg". For Zoomify images, pass in URL to property file or url containing "TileGroup". All other urls won't be recognized and ITVErrorDelegate will be noticed.
     */
    fileprivate func loadImage(_ imageUrl: String) {
        
        if imageUrl.contains(IIIFImageDescriptor.propertyFile) ||
            imageUrl.contains(ZoomifyImageDescriptor.propertyFile) {
            // address is prepared for loading
            self.url = imageUrl
        }
        else if imageUrl.lowercased().contains("/full/full/0/default.jpg") {
            // IIIF image, but url needs to be modified in order to download image information first
            self.url = imageUrl.replacingOccurrences(of: "full/full/0/default.jpg", with: IIIFImageDescriptor.propertyFile, options: .caseInsensitive, range: imageUrl.startIndex..<imageUrl.endIndex)
        }
        else if imageUrl.contains("TileGroup") {
            // Zoomify image, but url needs to be modified in order to download image information first
            let endIndex = imageUrl.range(of: "TileGroup")!.lowerBound
            let startIndex = imageUrl.startIndex
            self.url = imageUrl.substring(with: startIndex..<endIndex) + ZoomifyImageDescriptor.propertyFile
        }
        else {
            // try one and decide by result
            var testUrl = imageUrl
            if testUrl.characters.last != "/" {
                testUrl += "/"
            }
            
            if testUrlContent(testUrl + ZoomifyImageDescriptor.propertyFile) {
                self.url = testUrl + ZoomifyImageDescriptor.propertyFile
            }
            else if testUrlContent(testUrl + IIIFImageDescriptor.propertyFile) {
                self.url = testUrl + IIIFImageDescriptor.propertyFile
            }
            else {
                let error = NSError(domain: Constants.TAG, code: 100, userInfo: [Constants.USERINFO_KEY:"Url \(imageUrl) does not support IIIF or Zoomify API."])
                itvDelegate?.didFinishLoading(error: error)
            }
        }
    }
}

/// MARK: UIScrollViewDelegate implementation
extension ITVScrollView: UIScrollViewDelegate {
    
    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // decide the way of double tap zoom
        if zoomScale >= maximumZoomScale {
            doubleTapToZoom = false
        } else if zoomScale <= minimumZoomScale {
            doubleTapToZoom = true
        } else if lastZoomScale != zoomScale {
            doubleTapToZoom = (lastZoomScale < zoomScale)
        }
        lastZoomScale = zoomScale
        
        // limit bounce scale to prevent incorrect placed tiles
        if zoomScale < minBounceScale {
            zoomScale = minBounceScale
        } else if zoomScale > maxBounceScale {
            zoomScale = maxBounceScale
        }
        
        // center the image as it becomes smaller than the size of the screen
        let boundsSize = bounds.size
        let f = containerView.frame
        containerView.frame.origin.x = (f.size.width < boundsSize.width) ? (boundsSize.width - f.size.width) / 2 : 0
        containerView.frame.origin.y = (f.size.height < boundsSize.height) ? (boundsSize.height - f.size.height) / 2 : 0
    }
    
    public func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        changeLevel(forScale: scale)
    }
    
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return containerView
    }
}
