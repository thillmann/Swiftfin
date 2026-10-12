//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct RotateContentView: UIViewRepresentable {

    enum Transition: Equatable {
        case fade
        case slideFromLeading
        case slideFromTrailing
        case parallaxFromLeading
        case parallaxFromTrailing
    }

    @ObservedObject
    var proxy: Proxy

    func makeUIView(context: Context) -> UIRotateContentView {
        UIRotateContentView(initialView: nil, proxy: proxy)
    }

    func updateUIView(_ uiView: UIRotateContentView, context: Context) {}

    class Proxy: ObservableObject {

        weak var rotateContentView: UIRotateContentView?

        func update(
            transition: Transition = .fade,
            _ content: () -> any View
        ) {

            let newHostingController = UIHostingController(rootView: AnyView(content()), ignoreSafeArea: true)
            newHostingController.view.translatesAutoresizingMaskIntoConstraints = false
            newHostingController.view.backgroundColor = .clear

            rotateContentView?.update(
                with: newHostingController.view,
                transition: transition
            )
        }
    }
}

class UIRotateContentView: UIView {

    private(set) var currentView: UIView?
    private var parallaxAnimator: UIViewPropertyAnimator?
    private var updateGeneration = 0
    var proxy: RotateContentView.Proxy

    init(initialView: UIView?, proxy: RotateContentView.Proxy) {
        self.proxy = proxy

        super.init(frame: .zero)

        proxy.rotateContentView = self

        guard let initialView else { return }

        initialView.translatesAutoresizingMaskIntoConstraints = false
        initialView.alpha = 0

        addSubview(initialView)
        NSLayoutConstraint.activate([
            initialView.topAnchor.constraint(equalTo: topAnchor),
            initialView.bottomAnchor.constraint(equalTo: bottomAnchor),
            initialView.leftAnchor.constraint(equalTo: leftAnchor),
            initialView.rightAnchor.constraint(equalTo: rightAnchor),
        ])

        self.currentView = initialView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        with newView: UIView?,
        transition: RotateContentView.Transition = .fade
    ) {
        updateGeneration += 1
        let generation = updateGeneration

        prepareForTransition()

        guard let newView else {
            let outgoingView = currentView
            currentView = nil

            UIView.animate(withDuration: 0.3) {
                outgoingView?.alpha = 0
            } completion: { _ in
                guard self.updateGeneration == generation else { return }

                outgoingView?.removeFromSuperview()
            }
            return
        }

        newView.translatesAutoresizingMaskIntoConstraints = false
        newView.alpha = 0

        addSubview(newView)
        NSLayoutConstraint.activate([
            newView.topAnchor.constraint(equalTo: topAnchor),
            newView.bottomAnchor.constraint(equalTo: bottomAnchor),
            newView.leftAnchor.constraint(equalTo: leftAnchor),
            newView.rightAnchor.constraint(equalTo: rightAnchor),
        ])

        guard let outgoingView = currentView else {
            currentView = newView

            UIView.animate(withDuration: 0.3) {
                newView.alpha = 1
            } completion: { _ in
                guard self.updateGeneration == generation else { return }

                newView.alpha = 1
            }
            return
        }

        currentView = newView

        switch transition {
        case .fade:
            updateWithFade(newView, outgoingView: outgoingView, generation: generation)
        case .slideFromLeading:
            updateWithSlide(newView, outgoingView: outgoingView, direction: -1, generation: generation)
        case .slideFromTrailing:
            updateWithSlide(newView, outgoingView: outgoingView, direction: 1, generation: generation)
        case .parallaxFromLeading:
            updateWithParallax(newView, outgoingView: outgoingView, direction: -1, generation: generation)
        case .parallaxFromTrailing:
            updateWithParallax(newView, outgoingView: outgoingView, direction: 1, generation: generation)
        }
    }

    private func prepareForTransition() {
        parallaxAnimator?.stopAnimation(true)
        parallaxAnimator = nil

        subviews
            .filter { $0 !== currentView }
            .forEach { $0.removeFromSuperview() }

        currentView?.alpha = 1
        currentView?.transform = .identity
        currentView?.mask = nil
    }

    private func updateWithFade(_ newView: UIView, outgoingView: UIView, generation: Int) {
        UIView.animate(withDuration: 0.3) {
            newView.alpha = 1
            outgoingView.alpha = 0
        } completion: { _ in
            guard self.updateGeneration == generation else { return }

            outgoingView.removeFromSuperview()
        }
    }

    private func updateWithSlide(
        _ newView: UIView,
        outgoingView: UIView,
        direction: CGFloat,
        generation: Int
    ) {
        let incomingOffset = max(bounds.width * 0.12, 120) * direction
        let outgoingOffset = max(bounds.width * 0.05, 60) * -direction

        newView.alpha = 1
        newView.transform = CGAffineTransform(translationX: incomingOffset, y: 0)
            .scaledBy(x: 1.04, y: 1.04)

        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            usingSpringWithDamping: 0.92,
            initialSpringVelocity: 0.22,
            options: [.curveEaseOut, .beginFromCurrentState]
        ) {
            newView.transform = .identity
            outgoingView.transform = CGAffineTransform(translationX: outgoingOffset, y: 0)
                .scaledBy(x: 1.02, y: 1.02)
        } completion: { _ in
            guard self.updateGeneration == generation else { return }

            outgoingView.removeFromSuperview()
        }
    }

    private func updateWithParallax(
        _ newView: UIView,
        outgoingView: UIView,
        direction: CGFloat,
        generation: Int
    ) {
        layoutIfNeeded()

        let imageTravel = bounds.width * 0.08
        let incomingOffset = imageTravel * direction
        let outgoingOffset = imageTravel * -direction
        let revealMask = UIView(
            frame: CGRect(
                x: direction > 0 ? newView.bounds.width : 0,
                y: 0,
                width: 0,
                height: newView.bounds.height
            )
        )

        revealMask.backgroundColor = .black
        newView.mask = revealMask
        newView.alpha = 1
        newView.transform = CGAffineTransform(translationX: incomingOffset, y: 0)

        let timingParameters = UICubicTimingParameters(
            controlPoint1: CGPoint(x: 0.8, y: 0),
            controlPoint2: CGPoint(x: 0.2, y: 1)
        )
        let animator = UIViewPropertyAnimator(
            duration: 0.75,
            timingParameters: timingParameters
        )

        animator.addAnimations {
            revealMask.frame = newView.bounds
            newView.transform = .identity
            outgoingView.transform = CGAffineTransform(
                translationX: outgoingOffset,
                y: 0
            )
        }
        animator.addCompletion { [weak self, weak outgoingView] _ in
            guard let self else { return }

            guard self.updateGeneration == generation else { return }

            outgoingView?.removeFromSuperview()
            newView.mask = nil

            self.parallaxAnimator = nil
        }

        parallaxAnimator = animator
        animator.startAnimation()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        currentView?.hitTest(point, with: event)
    }
}
