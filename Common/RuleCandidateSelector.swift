//
//  RuleCandidateSelector.swift
//  Tracery
//
//  Created by Benzi on 10/03/17.
//  Copyright © 2017 Benzi Ahamed. All rights reserved.
//

import Foundation

public protocol RuleCandidateSelector {
    func pick(count: Int) -> Int
}


class PickFirstContentSelector : RuleCandidateSelector {
    private init() { }
    static let shared = PickFirstContentSelector()
    func pick(count: Int) -> Int {
        return 0
    }
}


private extension MutableCollection where Indices.Iterator.Element == Index {
    /// Shuffles the contents of this collection.
    mutating func shuffle() {
        let c = count
        guard c > 1 else { return }
        
        for (firstUnshuffled , unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
            let d: IndexDistance = numericCast(arc4random_uniform(numericCast(unshuffledCount)))
            guard d != 0 else { continue }
            let i = index(firstUnshuffled, offsetBy: d)
            swap(&self[firstUnshuffled], &self[i])
        }
    }
}

private extension Sequence {
    /// Returns an array with the contents of this sequence, shuffled.
    func shuffled() -> [Iterator.Element] {
        var result = Array(self)
        result.shuffle()
        return result
    }
}

class DefaultContentSelector : RuleCandidateSelector {
    
    var indices:[Int]
    var index: Int = 0
    
    init(_ count: Int) {
        indices = [Int]()
        for i in 0..<count {
            indices.append(i)
        }
        indices.shuffle()
    }
    
    func pick(count: Int) -> Int {
        assert(indices.count == count)
        if index >= count {
            indices.shuffle()
            index = 0
        }
        defer { index += 1 }
        return indices[index]
    }
    
}

