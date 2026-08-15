"""A small Whitespace assembler and interpreter.

Whitespace (Edwin Brady and Chris Morris, 2003) ignores every character that is
not space, tab, or linefeed, so a program can hide inside ordinary text. It is
stack-based and Turing complete: arithmetic, a heap, subroutines, jumps, and
character and numeric I/O.

Run this file directly and it builds the talk's closing joke -- the health check
endpoint, in a language with no visible syntax:

    python3 scripts/whitespace.py            # generate, show, run
    python3 scripts/whitespace.py --emit     # write examples/healthcheck.ws

Imported as a module it gives you `Asm` (emit instructions) and `run` (execute
them), which is what scripts/make-polyglot.py uses.

Encoding, for reference. Numbers are sign-first (Space = +, Tab = -), then
binary most significant bit first with Space = 0 and Tab = 1, terminated by a
linefeed. Labels are any run of spaces and tabs, also linefeed-terminated.

    IMP        instruction              tokens
    [S]        push n                   S S  <num>
               dup                      S L S
               swap                     S L T
               drop                     S L L
    [T][S]     add / sub / mul          T S S S | T S S T | T S S L
               div / mod                T S T S | T S T T
    [T][T]     store / retrieve         T T S   | T T T
    [L]        mark label               L S S <label>
               call / jump              L S T <label> | L S L <label>
               jump if zero / negative   L T S <label> | L T T <label>
               return / end             L T L | L L L
    [T][L]     print char / print num   T L S S | T L S T
               read char / read num     T L T S | T L T T
"""

from __future__ import annotations

import sys

S, T, L = " ", "\t", "\n"


def _num(n: int) -> str:
    """Sign, then binary MSB-first, then LF."""
    sign = S if n >= 0 else T
    bits = "".join(S if b == "0" else T for b in format(abs(n), "b"))
    return sign + bits + L


def _label(name: str) -> str:
    """Any run of spaces/tabs works; use the binary of a stable id."""
    return "".join(S if b == "0" else T for b in format(abs(hash(name)) % (1 << 24), "024b")) + L


class Asm:
    """Accumulate Whitespace instructions. Every method returns self."""

    def __init__(self) -> None:
        self.out: list[str] = []

    def _e(self, tok: str) -> "Asm":
        self.out.append(tok)
        return self

    # stack
    def push(self, n: int) -> "Asm":   return self._e(S + S + _num(n))
    def dup(self) -> "Asm":            return self._e(S + L + S)
    def swap(self) -> "Asm":           return self._e(S + L + T)
    def drop(self) -> "Asm":           return self._e(S + L + L)

    # arithmetic
    def add(self) -> "Asm":            return self._e(T + S + S + S)
    def sub(self) -> "Asm":            return self._e(T + S + S + T)
    def mul(self) -> "Asm":            return self._e(T + S + S + L)

    # heap
    def store(self) -> "Asm":          return self._e(T + T + S)
    def load(self) -> "Asm":           return self._e(T + T + T)

    # flow
    def mark(self, name: str) -> "Asm":   return self._e(L + S + S + _label(name))
    def call(self, name: str) -> "Asm":   return self._e(L + S + T + _label(name))
    def jump(self, name: str) -> "Asm":   return self._e(L + S + L + _label(name))
    def jz(self, name: str) -> "Asm":     return self._e(L + T + S + _label(name))
    def jneg(self, name: str) -> "Asm":   return self._e(L + T + T + _label(name))
    def ret(self) -> "Asm":               return self._e(L + T + L)
    def end(self) -> "Asm":               return self._e(L + L + L)

    # i/o
    def putc(self) -> "Asm":           return self._e(T + L + S + S)
    def putn(self) -> "Asm":           return self._e(T + L + S + T)

    # helpers
    def emit(self, text: str) -> "Asm":
        """Print a literal string, one push+putc per character."""
        for ch in text:
            self.push(ord(ch)).putc()
        return self

    def delay(self, ticks: int, tag: str) -> "Asm":
        """Busy-wait. Whitespace has no sleep, so burn a countdown.

        Wall-clock time depends entirely on interpreter speed, so this is a
        rough knob, not a duration.
        """
        self.push(ticks)
        self.mark(f"{tag}_loop")
        self.push(1).sub().dup()
        self.jz(f"{tag}_done")
        self.jump(f"{tag}_loop")
        self.mark(f"{tag}_done")
        self.drop()
        return self

    def source(self) -> str:
        return "".join(self.out)


# --- interpreter --------------------------------------------------------------


def _parse(src: str):
    """Tokens -> [(op, arg)], plus a label table. Stops at 'end'.

    Stopping at 'end' is what makes a polyglot possible: everything after the
    terminator is unreachable, so a Python program can live there. Note that
    interpreters differ here -- some parse the whole file up front and will
    choke on trailing junk. This one does not.
    """
    tk = [c for c in src if c in (S, T, L)]
    i, prog = 0, []

    def num():
        nonlocal i
        sign = -1 if tk[i] == T else 1
        i += 1
        bits = ""
        while tk[i] != L:
            bits += "0" if tk[i] == S else "1"
            i += 1
        i += 1
        return sign * (int(bits, 2) if bits else 0)

    def lbl():
        nonlocal i
        out = ""
        while tk[i] != L:
            out += "0" if tk[i] == S else "1"
            i += 1
        i += 1
        return out

    while i < len(tk):
        if tk[i] == S:                                     # stack
            i += 1
            if tk[i] == S:
                i += 1
                prog.append(("push", num()))
            else:                                          # S L x
                i += 1
                prog.append(({S: "dup", T: "swap", L: "drop"}[tk[i]], None))
                i += 1
        elif tk[i] == T and tk[i + 1] == S:                # arithmetic
            i += 2
            key = tk[i] + tk[i + 1]
            i += 2
            prog.append(({S + S: "add", S + T: "sub", S + L: "mul",
                          T + S: "div", T + T: "mod"}[key], None))
        elif tk[i] == T and tk[i + 1] == T:                # heap
            i += 2
            prog.append(("store" if tk[i] == S else "load", None))
            i += 1
        elif tk[i] == T and tk[i + 1] == L:                # i/o
            i += 2
            key = tk[i] + tk[i + 1]
            i += 2
            prog.append(({S + S: "putc", S + T: "putn",
                          T + S: "getc", T + T: "getn"}[key], None))
        elif tk[i] == L:                                   # flow
            i += 1
            a, b = tk[i], tk[i + 1]
            i += 2
            if a == L and b == L:
                prog.append(("end", None))
                break                                      # <- polyglot lives here
            op = {(S, S): "mark", (S, T): "call", (S, L): "jump",
                  (T, S): "jz", (T, T): "jneg", (T, L): "ret"}[(a, b)]
            prog.append((op, lbl() if op != "ret" else None))
        else:
            raise SyntaxError(f"bad token at {i}")

    labels = {arg: k for k, (op, arg) in enumerate(prog) if op == "mark"}
    return prog, labels


def run(src: str, out=None, max_steps: int = 50_000_000) -> str:
    """Execute Whitespace source. Returns the output if `out` is None."""
    prog, labels = _parse(src)
    stack: list[int] = []
    heap: dict[int, int] = {}
    calls: list[int] = []
    buf: list[str] = []
    pc = steps = 0

    while pc < len(prog):
        if (steps := steps + 1) > max_steps:
            raise RuntimeError("step limit exceeded")
        op, arg = prog[pc]
        pc += 1

        if op == "push":    stack.append(arg)
        elif op == "dup":   stack.append(stack[-1])
        elif op == "swap":  stack[-1], stack[-2] = stack[-2], stack[-1]
        elif op == "drop":  stack.pop()
        elif op == "add":   b, a = stack.pop(), stack.pop(); stack.append(a + b)
        elif op == "sub":   b, a = stack.pop(), stack.pop(); stack.append(a - b)
        elif op == "mul":   b, a = stack.pop(), stack.pop(); stack.append(a * b)
        elif op == "div":   b, a = stack.pop(), stack.pop(); stack.append(a // b)
        elif op == "mod":   b, a = stack.pop(), stack.pop(); stack.append(a % b)
        elif op == "store": v, k = stack.pop(), stack.pop(); heap[k] = v
        elif op == "load":  stack.append(heap[stack.pop()])
        elif op == "mark":  pass
        elif op == "call":  calls.append(pc); pc = labels[arg]
        elif op == "jump":  pc = labels[arg]
        elif op == "jz":    pc = labels[arg] if stack.pop() == 0 else pc
        elif op == "jneg":  pc = labels[arg] if stack.pop() < 0 else pc
        elif op == "ret":   pc = calls.pop()
        elif op == "end":   break
        elif op == "putc":
            ch = chr(stack.pop())
            if out is None: buf.append(ch)
            else: out.write(ch); out.flush()
        elif op == "putn":
            s = str(stack.pop())
            if out is None: buf.append(s)
            else: out.write(s); out.flush()
        else:
            raise NotImplementedError(op)

    return "".join(buf)


# --- the talk's closing joke --------------------------------------------------


def main() -> None:
    src = Asm().emit("OK\n").end().source()

    if "--emit" in sys.argv:
        with open("examples/healthcheck.ws", "w") as fh:
            fh.write(src)
        print("wrote examples/healthcheck.ws")

    print(f"source is {len(src)} bytes, {len(set(src))} distinct characters:")
    print("  ", sorted(repr(c) for c in set(src)))
    print("\nwhat you see when you open the file:")
    print("  |" + src.replace(L, "\n  |"))
    print("\nwhat is actually there (cat -A):")
    print("  " + src.replace(S, "·").replace(T, "→").replace(L, "$\n  "))
    print("output when run:", repr(run(src)))
    assert run(src) == "OK\n", "the health check is unhealthy"
    print("health check: PASS")


if __name__ == "__main__":
    main()
