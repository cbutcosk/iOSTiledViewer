//
//  ITVLicenceView.swift
//  Pods
//
//  Created by Jakub Fiser on 04/11/2016.
//
//

import UIKit

class ITVLicenceView: UIView {

    fileprivate var maximumWidth: CGFloat!
    fileprivate var maximumHeight: CGFloat!
    
    var imageDescriptor: ITVImageDescriptor? {
        didSet {
            if imageDescriptor != nil {
                setup(imageDescriptor!)
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        backgroundColor = UIColor.clear
    }
    
    fileprivate func setup(_ image: ITVImageDescriptor) {
        guard let licence = (image as? IIIFImageDescriptor)?.license else {
            // The licence information can currently be only on IIIF Image
            return
        }
        
        // TODO: Get scroll view dimensions
        let display = UIScreen.main.bounds
        maximumWidth = display.width
        maximumHeight = display.height
        
        var viewsArray:[UIView] = [self]
        if let value = licence.attribution {
            let label = UILabel()
            let attributedOptions: [String:Any] = [NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType, NSCharacterEncodingDocumentAttribute: String.Encoding.utf8.rawValue]
            label.attributedText = try? NSAttributedString(data: value.data(using: .utf8)!, options: attributedOptions, documentAttributes: nil)
            label.numberOfLines = 0
            insertStacked(view: label, stack: viewsArray)
            viewsArray.append(label)
        }
        if let value = licence.license {
            let label = UILabel()
            label.text = value
            label.numberOfLines = 0
            insertStacked(view: label, stack: viewsArray)
            viewsArray.append(label)
        }
        if let value = licence.logo {
            // TODO: logo value does not have to be an url
            URLSession.shared.dataTask(with: URL(string: value)!, completionHandler: { (data, response, error) in
                if data != nil {
                    let image = UIImage(data: data!)
                    let imageView = UIImageView(image: image)
                    imageView.contentMode = .scaleAspectFit
                    self.insertStacked(view: imageView, stack: viewsArray)
                }
            }).resume()
        }
    }
    
    fileprivate func insertStacked(view: UIView, stack: [UIView]) {
        if !Thread.current.isMainThread {
            DispatchQueue.main.async {
                self.insertStacked(view: view, stack: stack)
            }
            return
        }
        
        removeConstraints(constraints.filter( {$0.firstAttribute == .top} ))
        addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        addConstraints([
            NSLayoutConstraint(item: view, attribute: .trailing, relatedBy: .equal, toItem: self, attribute: .trailing, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: view, attribute: .bottom, relatedBy: .equal, toItem: stack.last, attribute: (stack.last == self ? .bottom : .top), multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: view, attribute: .leading, relatedBy: .greaterThanOrEqual, toItem: self, attribute: .leading, multiplier: 1.0, constant: 0),
            NSLayoutConstraint(item: view, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top, multiplier: 1.0, constant: 0)
            ])
    }
}
