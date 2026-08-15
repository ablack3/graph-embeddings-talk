# The Riesz representation theorem, and why statisticians should care

A ~9-minute lecture script, written to be **spoken**, for the audio clip played
on the "How I actually study now" slide. It is an example of the workflow the
talk describes: conversation → structured markdown → script → audio.

::: note
**On the voice.** Play this in your own voice, or with a stock/licensed synthetic
voice you have rights to. Don't clone a named celebrity — for a recorded talk
that gets posted, an unlicensed voice likeness is a real problem and not a funny
one.

The joke on stage survives this completely, because the joke was never the
specific person. It's the contrast between a calm, expensive-sounding narrator
and the phrase "Riesz representation theorem." Any serene stock voice delivers
it. In the script the line is *"a synthetic voice that sounds suspiciously like a
certain Oscar winner"* — which gets the laugh without you having made the thing.
:::

---

## 0. Spelling and disambiguation, 20 seconds

It's **Riesz** — Frigyes Riesz, Hungarian, 1907. Rhymes roughly with "reece".
Not "Reitz".

And be careful, because *two* different theorems carry his name. There's the one
about representing functionals on continuous functions as integrals against a
measure. That's not this one. This one is the Hilbert space version, and it is
the one that quietly underwrites half of modern statistics.

---

## 1. A Hilbert space is a place where you can do geometry

Start with what you already know. In ordinary Euclidean space you have a dot
product, and from the dot product you get everything else: length is the square
root of a vector with itself, and two vectors are perpendicular when their dot
product is zero. Angle, distance, projection — all of it comes from that one
operation.

A **Hilbert space** is what you get when you insist on keeping that structure but
drop the requirement that the space be finite-dimensional. Formally: a vector
space with an inner product, which is *complete* — meaning sequences that ought
to converge actually do, so limits don't fall out of the space.

Here is the one statisticians live in, and once you see it you can't unsee it.

Take all random variables with finite variance on some probability space. That's
a vector space — you can add random variables and scale them. Now define the
inner product of $X$ and $Y$ to be the **expectation of their product**,
$\langle X, Y \rangle = E[XY]$.

Check what that gives you. The norm squared of $X$ is $E[X^2]$ — the second
moment. If $X$ is centered, the norm squared is the **variance**, so the length
of a random variable is its standard deviation. The inner product of two centered
variables is their **covariance**. And two centered variables are *orthogonal* —
perpendicular — exactly when they are **uncorrelated**.

So correlation is the cosine of an angle. That's not an analogy. That is what it
is. This space is called $L^2$, and it is a Hilbert space.

And once you're in a Hilbert space, the single most powerful move available is
**projection**: given a subspace, every point has a unique closest point in it,
and the error is orthogonal to the subspace.

Which is the whole of least squares. Ordinary regression is projecting $Y$ onto
the span of your covariates. The normal equations are just the statement that the
residual is perpendicular to every regressor. And conditional expectation,
$E[Y \mid X]$, is exactly the projection of $Y$ onto the closed subspace of all
functions of $X$ — which is precisely why it is the best predictor under squared
error, and why the residual is uncorrelated with anything you could have built
from $X$.

That is a lot of statistics falling out of one picture.

---

## 2. The theorem

Now the theorem itself, which takes one sentence.

A **linear functional** is a map that eats a vector and returns a single number,
linearly. "Take the third coordinate." "Integrate this function against a
weight." "Evaluate this function at the point $x$." "Take the expectation."

The Riesz representation theorem says:

> Every **continuous** linear functional on a Hilbert space is an inner product
> with one fixed vector — and that vector is unique.

If $L$ is a continuous linear functional on $H$, there is exactly one $h$ in $H$
with $L(f) = \langle f, h \rangle$ for every $f$. That $h$ is called the **Riesz
representer** of $L$.

Sit with how strange that is. A functional is a *machine*. An element of the
space is a *point*. The theorem says that in a Hilbert space these are the same
kind of object. Every machine is secretly a point, and it acts by taking an inner
product with itself. The space and its dual are the same space.

The word *continuous* is carrying the whole thing, and it means "bounded" — the
output can't blow up when the input is small. Drop it and the theorem is false;
there are wild unbounded functionals with no representer at all. So in practice
the entire game is: **prove your functional is bounded, and then go find its
representer.**

---

## 3. Where kernels actually come from

Here's the first payoff, and it explains a piece of machine learning that is
usually presented as a trick.

Consider a space of functions, and consider the functional "evaluate at the point
$x$" — hand it a function $f$, it returns the number $f(x)$. Perfectly linear.

Is it continuous? In general, no. In $L^2$ it's not even *defined*, because
elements of $L^2$ are equivalence classes that ignore sets of measure zero, so
"the value at $x$" isn't a thing.

A **reproducing kernel Hilbert space** is defined as a space of functions where
evaluation *is* continuous. That's the whole definition. It's an assumption.

But now apply Riesz. Evaluation-at-$x$ is a continuous linear functional, so it
has a representer — some function, call it $k_x$, with

$$f(x) = \langle f, k_x \rangle \quad \text{for every } f.$$

Define $k(x, y) = \langle k_x, k_y \rangle$, and there is your kernel. It is not a
clever trick someone invented. It is the Riesz representer of point evaluation,
and it exists the moment you assume evaluation is continuous.

Everything downstream follows: the representer theorem, which says the solution
to a penalized fit lands in the span of the kernel at your data points; kernel
ridge regression; support vector machines; Gaussian processes, where the
covariance function is that same kernel. The reason you never have to touch the
infinite-dimensional feature space is that Riesz already collapsed it into a
finite computation on your $n$ observations.

---

## 4. The one that surprised me: inverse probability weights

And here's the payoff I did not see coming, which is from causal inference.

Suppose your target isn't a prediction but a *number* — an average treatment
effect, an average derivative, a policy value. Many of these are **linear
functionals of the regression function**. The ATE, for instance, is the average
over the population of $g(1, X) - g(0, X)$, where $g$ is the outcome regression.
Linear in $g$.

So: is it continuous? If it is — Riesz hands you a representer $\alpha_0$, a
function with

$$E[m(W, g)] = E[\alpha_0(W)\, g(W)].$$

Now compute what $\alpha_0$ is for the ATE.

It's the **inverse propensity weight**. Treatment over the propensity score,
minus one-minus-treatment over one-minus-the-propensity-score.

I want to be clear about the direction of that statement. Inverse probability
weighting was not derived by someone reasoning about Hilbert spaces. It was
invented by Horvitz and Thompson in 1952 to fix unequal sampling, and it has been
justified a dozen ways since. But if you ask "what is the Riesz representer of
the ATE functional," out falls the propensity weight. The thing people write down
by intuition is the unique element the theorem guarantees.

And that reframing turns out to be *productive*, not just tidy. It's the basis of
**automatic debiased machine learning** — Chernozhukov and coauthors — where
instead of modelling the propensity score, you estimate the Riesz representer
directly by minimizing a loss that follows from the theorem. Same for the
efficient influence function and the semiparametric efficiency bound: those are
statements about projections and representers in $L^2$.

So the geometry isn't decoration. It tells you what the bias-correction term has
to be, before you've chosen a single estimator.

---

## 5. What to actually remember

Four things.

One. $L^2$ is a Hilbert space where length is standard deviation, inner product
is covariance, and orthogonal means uncorrelated.

Two. In that space, conditional expectation and least squares are the same
operation: orthogonal projection onto a subspace.

Three. Riesz says every continuous linear functional on a Hilbert space is an
inner product with a unique vector. Machines are points.

Four. That vector is often something you already use and thought was a
convention. In an RKHS it's the kernel. For the average treatment effect it's the
inverse propensity weight.

The theorem doesn't give you new objects. It tells you the ones you have were
inevitable.

---

## Production notes

- **Runtime:** about 1,450 words, so 9–10 minutes at a normal narration pace.
- **For the talk you only need §0 and the first paragraph of §1** — roughly 15
  seconds. Cut on "…rhymes roughly with *reece*. Not *Reitz*." The correction is
  the funniest part and it's the part you were wrong about, which is better.
- Read the display equations as words; don't let TTS attempt the LaTeX. The two
  that matter, spoken: *"f of x equals the inner product of f with k-sub-x"* and
  *"the expected value of m equals the expected value of alpha-zero times g."*
- If you generate audio, keep the API call in `scripts/` next to
  `whitespace.py` so the repo stays reproducible, and keep the key out of git.

## References

- Riesz, F. (1907). *Sur une espèce de géométrie analytique des systèmes de
  fonctions sommables.*
- Aronszajn, N. (1950). *Theory of reproducing kernels.* Trans. AMS 68.
- Horvitz, D. & Thompson, D. (1952). *A generalization of sampling without
  replacement from a finite universe.* JASA 47.
- Chernozhukov, V., Newey, W., Quintas-Martínez, V. & Syrgkanis, V. (2021).
  *Automatic debiased machine learning via Riesz regression.*
- Tsiatis, A. (2006). *Semiparametric Theory and Missing Data* — chapters 2–4 are
  the Hilbert-space geometry of influence functions, done slowly.
