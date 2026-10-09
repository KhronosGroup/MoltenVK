// Copyright (c) 2026 Jean-Philippe Meunier
// SPDX-License-Identifier: Apache-2.0
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <functional>
#include <vector>
struct MVKCommandEncoder;
struct MVKCommand {
    MVKCommand* _next = nullptr;
    bool released = false;
    std::function<void(MVKCommandEncoder*)> action;
    void encode(MVKCommandEncoder* encoder) { assert(!released); action(encoder); }
};
struct MVKCommandEncoder {
    uint32_t _multiviewPassIndex = 0;
    MVKCommand* _lastMultiviewPassCmd = nullptr;
    bool _isEncodingStopped = false;
    void endEncoding() { assert(_lastMultiviewPassCmd && !_lastMultiviewPassCmd->released); }
    void encodeCommandsImpl(MVKCommand*);
    void encodeCommands(MVKCommand* command) { encodeCommandsImpl(command); }
};
constexpr int VK_NOT_READY = 1;
struct MVKCommandBuffer {
    bool _canAcceptCommands = true, _isReusable = false;
    unsigned _commandCount = 0;
    MVKCommandEncoder* _immediateCmdEncoder = nullptr;
    int* _immediateCmdEncodingContext = nullptr;
    MVKCommand* _head = nullptr;
    MVKCommand* _tail = nullptr;
    int result = 0;
    int reportError(int error, const char*) { return error; }
    void setConfigurationResult(int error) { result = error; }
    void releaseCommands(MVKCommand* command) {
        while (command) { assert(!command->released); command->released = true; command = command->_next; }
    }
    void addCommand(MVKCommand*);
    void releaseRecordedCommands();
    void flushImmediateCmdEncoder();
};
#include "PrefillMethods.inc"
int main(int argc, char**) {
    // Model command sequencing for no prefill (0), deferred (1), and immediate (2/3).
    // Metal encoding, deferred reservations, and autorelease pools are outside this host test.
    for (unsigned style : {0u, 1u, 2u, 3u}) for (bool reusable : {false, true}) {
        if (argc > 1 && !reusable) continue;
        MVKCommandEncoder encoder;
        MVKCommandBuffer buffer;
        buffer._isReusable = reusable;
        bool immediate = style >= 2;
        buffer._immediateCmdEncoder = immediate ? new MVKCommandEncoder : nullptr;
        buffer._immediateCmdEncodingContext = immediate ? new int(0) : nullptr;
        std::vector<unsigned> seen;
        unsigned terminators[2]{};
        MVKCommand commands[8];
        for (unsigned subpass = 0; subpass < 2; ++subpass) {
            unsigned start = subpass * 3;
            commands[start].action = [&, start](auto* e) { e->_multiviewPassIndex = 0; e->_lastMultiviewPassCmd = &commands[start]; };
            commands[start + 1].action = [&, subpass](auto* e) { seen.push_back(10 * subpass + e->_multiviewPassIndex); };
            commands[start + 2].action = [&, subpass](auto* e) { ++terminators[subpass]; if (e->_multiviewPassIndex == 0) { ++e->_multiviewPassIndex; } };
        }
        commands[6].action = [&](auto*) { seen.push_back(99); };
        commands[7].action = [&](auto*) { seen.push_back(100); };
        for (auto& command : commands) { buffer.addCommand(&command); }
        if (!immediate) { encoder.encodeCommands(buffer._head); }
        assert((seen == std::vector<unsigned>{0, 1, 10, 11, 99, 100}));
        assert(terminators[0] == 2 && terminators[1] == 2);
        assert(buffer._commandCount == 8 && buffer._head == &commands[0] && buffer._tail == &commands[7]);
        unsigned retained = 0;
        for (auto* c = buffer._head; c; c = c->_next) { assert(!c->released); ++retained; }
        assert(retained == 8);
        if (style == 1 && !reusable) { buffer.releaseRecordedCommands(); }
        buffer.flushImmediateCmdEncoder();
        assert(!buffer._immediateCmdEncoder && !buffer._immediateCmdEncodingContext);
        if (style && !reusable) {
            assert(!buffer._head && !buffer._tail);
            for (const auto& command : commands) assert(command.released);
        } else { for (const auto& command : commands) assert(!command.released); }
        // Reset may flush and release again, but may never double-release a pooled command.
        buffer.flushImmediateCmdEncoder();
        buffer.releaseRecordedCommands();
        buffer.releaseRecordedCommands();
        for (const auto& command : commands) { assert(command.released); }
    }
    // A device loss inside a command stops the loop: the commands recorded after it are never encoded.
    {
        MVKCommandEncoder encoder;
        std::vector<unsigned> seen;
        MVKCommand commands[3];
        commands[0].action = [&](auto*) { seen.push_back(0); };
        commands[1].action = [&](auto* e) { seen.push_back(1); e->_isEncodingStopped = true; };
        commands[2].action = [&](auto*) { seen.push_back(2); };
        commands[0]._next = &commands[1];
        commands[1]._next = &commands[2];
        encoder.encodeCommands(&commands[0]);
        assert((seen == std::vector<unsigned>{0, 1}));
    }
    puts("no-prefill, deferred and immediate sequencing; reusable/one-time, two multiview subpasses; stop after loss: PASS");
}
