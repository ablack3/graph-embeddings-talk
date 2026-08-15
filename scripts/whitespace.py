"""Write -- and then actually run -- a program in the Whitespace language.

For the closing joke of the talk. The premise is that the smallest, most
load-bearing program at any tech company is the health-check endpoint: it
returns "OK", every load balancer on earth depends on it, and no human has
opened the file since 2019. So we rewrite it in a language whose entire
syntax is invisible.

    python3 scripts/whitespace.py            # generate, hexdump, run
    python3 scripts/whitespace.py --emit     # write examples/healthcheck.ws

Whitespace (Edwin Brady and Chris Morris, 2003) ignores every character
that is not space, tab, or linefeed -- so a program can hide inside
ordinary text. It is stack-based, Turing complete, and has arithmetic,
heap storage, subroutines and jumps. We need four instructions:

    [Space][Space] <sign> <binary> [LF]   push a number
    [Tab][LF][Space][Space]               pop, print as a character
    [LF][LF][LF]                          end program

Numbers are sign-first (Space = +, Tab = -), then binary, most significant
bit first, with Space = 0 and Tab = 1, terminated by a linefeed.
"""

import sys

S, T, L = " ", "\t", "\n"


def push(n: int) -> str:
    """[Space][Space] sign binary [LF]"""
    sign = S if n >= 0 else T
    bits = "".join(S if b == "0" else T for b in format(abs(n), "b"))
    return S + S + sign + bits + L


PRINT_CHAR = T + L + S + S
END = L + L + L


def compile_message(msg: str) -> str:
    return "".join(push(ord(ch)) + PRINT_CHAR for ch in msg) + END


# --- a Whitespace interpreter, so the joke is checkable ----------------------


def run(src: str) -> str:
    toks = [c for c in src if c in (S, T, L)]
    i, stack, out = 0, [], []

    def read_number():
        nonlocal i
        sign = -1 if toks[i] == T else 1
        i += 1
        bits = ""
        while toks[i] != L:
            bits += "0" if toks[i] == S else "1"
            i += 1
        i += 1  # consume the terminating LF
        return sign * (int(bits, 2) if bits else 0)

    while i < len(toks):
        if toks[i] == S:  # stack IMP
            i += 1
            if toks[i] == S:
                i += 1
                stack.append(read_number())
            else:
                raise NotImplementedError("only 'push' is needed here")
        elif toks[i] == T and toks[i + 1] == L:  # I/O IMP
            i += 2
            if toks[i : i + 2] == [S, S]:
                i += 2
                out.append(chr(stack.pop()))
            else:
                raise NotImplementedError("only 'print char' is needed here")
        elif toks[i : i + 3] == [L, L, L]:  # end program
            break
        else:
            raise SyntaxError(f"unexpected token at {i}")
    return "".join(out)


def main() -> None:
    src = compile_message("OK\n")

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
