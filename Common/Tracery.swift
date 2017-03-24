//
//  Tracery.swift
//  
//
//  Created by Benzi on 10/03/17.
//
//

import Foundation

struct RuleMapping {
    let candidates: [RuleCandidate]
    var selector: RuleCandidateSelector
    
    func select() -> RuleCandidate? {
        let index = selector.pick(count: candidates.count)
        guard index >= 0 && index < candidates.count else { return nil }
        return candidates[index]
    }
}

struct RuleCandidate {
    let text: String
    var nodes: [ParserNode]
}


public class TraceryOptions {
    public var tagStorageType = TaggingPolicy.unilevel
    public var isRuleAnalysisEnabled = true
    
    public init() { }
}

extension TraceryOptions {
    static let defaultSet = TraceryOptions()
}

public class Tracery {
    
    var ruleSet: [String: RuleMapping]
    var mods: [String: (String,[String])->String]
    var tagStorage: TagStorage
    var contextStack: ContextStack
    
    public var ruleNames: [String] { return ruleSet.keys.map { $0 } }
    
    convenience public init() {
        self.init {[:]}
    }
    
    let options: TraceryOptions
    
    public init(_ options: TraceryOptions = TraceryOptions.defaultSet, rules: () -> [String: Any]) {
        
        self.options = options
        mods = [:]
        ruleSet = [:]
        tagStorage = options.tagStorageType.storage()
        contextStack = ContextStack()
        tagStorage.tracery = self
        
        let rules = rules()
        
        rules.forEach { rule, value in
            add(rule: rule, definition: value)
        }
        
        analyzeRuleBook()
        
        info("tracery ready")
    }
    
    // add a rule and its definition to
    // the mapping table
    // errors if any are returned
    func add(rule: String, definition value: Any) {
        
        // validate the rule name
        let tokens = Lexer.tokens(rule)
        guard tokens.count == 1, case let .text(name) = tokens[0] else {
            error("rule '\(rule)' ignored - names must be plaintext")
            return
        }
        if name.contains("#") || name.contains("[") {
            error("rule '\(rule)' ignored - names cannot contain # or [")
            return
        }
        
        if ruleSet[rule] != nil {
            warn("duplicate rule '\(rule)', using latest definition")
        }
        
        let values: [String]
        
        if let provider = value as? RuleCandidatesProvider {
            values = provider.candidates
        }
        else if let string = value as? String {
            values = [string]
        }
        else if let array = value as? [String] {
            values = array
        }
        else if let array = value as? Array<CustomStringConvertible> {
            values = array.map { $0.description }
        }
        else {
            values = ["\(value)"]
        }
        
        var candidates = values.flatMap { createRuleCandidate(rule: rule, text: $0) }
        if candidates.count == 0 {
            warn("rule '\(rule)' does not have any definitions, will be ignored")
            return
        }
        
        let selector: RuleCandidateSelector
        if let s = value as? RuleCandidateSelector {
            selector = s
        }
        else if candidates.count == 1 {
            selector = PickFirstContentSelector.shared
        }
        else {
            // check if any of the candidates have a weight
            // attached? if so, we attach a weighted selector
            func hasWeights() -> Bool {
                for candidate in candidates {
                    if let last = candidate.nodes.last, case .weight = last {
                        return true
                    }
                }
                return false
            }
            if hasWeights() {
                var weights = [Int]()
                for i in candidates.indices {
                    let c = candidates[i]
                    if let last = c.nodes.last, case let .weight(value) = last {
                        weights.append(value)
                        // remove the weight node since we are done with it
                        candidates[i].nodes.removeLast()
                    }
                    else {
                        weights.append(1)
                    }
                }
                selector = WeightedSelector(weights)
            }
            else {
                selector = DefaultContentSelector(candidates.count)
            }
        }
        
        ruleSet[rule] = RuleMapping(candidates: candidates, selector: selector)
    }
    
    private func createRuleCandidate(rule:String, text: String) -> RuleCandidate? {
        let e = error
        do {
            info("checking rule '\(rule)' - \(text)")
            return RuleCandidate(
                text: text,
                nodes: try Parser.gen(Lexer.tokens(text))
            )
        }
        catch {
            e("rule '\(rule)' parse error - \(error) in definition - \(text)")
            return nil
        }
    }
    
    public func add(modifier: String, transform: @escaping (String)->String) {
        if mods[modifier] != nil {
            warn("overwriting modifier '\(modifier)'")
        }
        mods[modifier] = { input, _ in
            return transform(input)
        }
    }
    
    public func add(call: String, transform: @escaping () -> ()) {
        if mods[call] != nil {
            warn("overwriting call '\(call)'")
        }
        mods[call] = { input, _ in
            transform()
            return input
        }
    }
    
    public func add(method: String, transform: @escaping (String, [String])->String) {
        if mods[method] != nil {
            warn("overwriting method '\(method)'")
        }
        mods[method] = transform
    }
    
    public func setCandidateSelector(rule: String, selector: RuleCandidateSelector) {
        guard ruleSet[rule] != nil else {
            warn("rule '\(rule)' not found to set selector")
            return
        }
        ruleSet[rule]?.selector = selector
    }
    
    public func expand(_ input: String, resetTags: Bool = true) -> String {
        do {
            if resetTags {
                ruleEvaluationLevel = 0
                tagStorage.removeAll()
            }
            return try eval(input)
        }
        catch {
            return "error: \(error)"
        }
    }
    
    public static var maxStackDepth = 256
    
    fileprivate(set) var ruleEvaluationLevel: Int = 0
    
    func incrementEvaluationLevel() throws {
        ruleEvaluationLevel += 1
        // trace("⚙️ depth: \(ruleEvaluationLevel)")
        if ruleEvaluationLevel > Tracery.maxStackDepth {
            error("stack overflow")
            throw ParserError.error("stack overflow")
        }
    }
    
    func decrementEvaluationLevel() {
        ruleEvaluationLevel = max(ruleEvaluationLevel - 1, 0)
        // trace("⚙️ depth: \(ruleEvaluationLevel)")
    }
}
