//
//  XStack.swift
//  DL4S
//
//  Created by Palle Klewitz on 16.10.19.
//  Copyright (c) 2019 - Palle Klewitz
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation


public extension XTensor {
    func unstacked(along axis: Int, withSourceLengths sourceLengths: [Int]) -> [XTensor<Element, Device>] {
        let sourceShapes = sourceLengths.map { length -> [Int] in
            var shape = self.shape
            shape[axis] = length
            return shape
        }
        let sourceBuffers = sourceShapes.map {
            Device.Memory.allocateBuffer(withShape: $0, type: Element.self)
        }
        Device.Engine.unstack(stacked: self.values, result: sourceBuffers, axis: axis)
        
        return sourceBuffers.enumerated().map { (i, buffer) in
            XTensor(
                using: buffer,
                context: self.requiresGradient ? XTensorContext(
                    tag: "unstack",
                    sources: [self],
                    backpropagate: [{ resultGradient -> XTensor<Element, Device> in
                        let sourceOffsets = sourceLengths.reduce(into: [0], {$0.append($0.last! + $1)})
                        let idx = Array(repeating: nil, count: axis) +
                            [sourceOffsets[i] ..< sourceOffsets[i] + sourceLengths[i]]
                        
                        var target = XTensor<Element, Device>(repeating: 0, shape: self.shape)
                        target[idx] = resultGradient
                        return target
                    }]
                ) : nil
            )
        }
    }
    
    init(stacking tensors: [Self], along axis: Int = 0) {
        precondition(0 ..< tensors[0].dim ~= axis, "Dimensionality of tensors must be in dimensionality range of source tensors")
        
        precondition(tensors.allSatisfy {
            $0.shape.count == tensors[0].shape.count &&
                zip($0.shape, tensors[0].shape)
                    .enumerated()
                    .allSatisfy {$0 == axis || $1.0 == $1.1}
        }, "All vector shapes must match except on concatenation axis.")
        
        let requiresGradient = tensors.contains(where: {$0.requiresGradient})
        
        let resultStackDimSize = tensors.map {$0.shape[axis]}
        let resultStackDimCount = resultStackDimSize.reduce(0, +)
        
        var resultShape = tensors[0].shape
        resultShape[axis] = resultStackDimCount
        
        let resultBuffer = Device.Memory.allocateBuffer(withShape: resultShape, type: Element.self)
        Device.Engine.stack(buffers: tensors.map {$0.values}, result: resultBuffer, axis: axis)
        
        self.init(
            using: resultBuffer,
            context: requiresGradient ? XTensorContext(
                tag: "stack",
                sources: tensors,
                backpropagate: tensors.indices.map { i in { resultGradient in
                    resultGradient.unstacked(along: axis, withSourceLengths: resultStackDimSize)[i]
                }}
            ) : nil
        )
    }
}

public func stack<Element, Device>(_ tensors: [XTensor<Element, Device>], along axis: Int = 0) -> XTensor<Element, Device> {
    XTensor(stacking: tensors, along: axis)
}
