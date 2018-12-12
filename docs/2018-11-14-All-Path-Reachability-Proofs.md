All-path Reachability Proofs
============================

This document describes how to advance towards showing that a goal is
reachable from a given pattern on any execution path.

Parts of this document are inspired by a picture of a whiteboard by
Grigore, parts of it are inspired by the one-path reachability document
quoted below.

Background
----------

[2018-11-08-One-Path-Reachability-Proofs.md](2018-11-08-One-Path-Reachability-Proofs.md)
describes a very similiar problem.

Problem description
-------------------

Let `φ(X)` be the start pattern. Let `ψ(X, Y)` be the goal we want to reach.
`•` will denote the one-path next. `○` will denote the all-path next, i.e.
`○ψ = ¬•¬ψ`. Unlike the above document, `◇` will denote all-path eventually,
i.e. `◇ψ = ⟐ψ`.

Then we want to show that

```
∀ X . φ(X) → ◇ ∃ Y . ψ(X, Y)
```

Questions
---------

How is allpath actually defined? Does it allow for infinite heat-cool cycles?

Assumptions
-----------

We assume that we have a full set of rewriting axioms, i.e. we know that
there are no other rewriting axioms.

We assume that our pattern `φ` is in the form `φ1 ∨ φ2 ∨ ... ∨ φn`, where each
`φi` is in a form on which we can do unification and we can apply axioms.

The algorithm will never finish if there are rewrite rules that can cycle
indefinitely without rewriting anything (e.g. heating-cooling rules without guards about when things should be heated/cooled).

Algorithm
---------

Let us assume that our axioms can be represented as `∀ Z . αi(Z) → •βi(Z)`
with `i` from `1` to `a`

1. If `φ` is bottom then we have succeeded.
1. We take one of the terms (`φ1`) from `φ`'s or expression.
1. We compute `Φ(X) = φ(X) ∧ ¬∃ Y . ψ(X, Y)`.
1. If `Φ(X)` cannot be computed, the algorithm fails.
1. If `Φ(X)` is `⊥` then we restart the algorithm with
   `φ = φ2 ∨ φ3 ∨ ... ∨ φn`.
1. We then compute `Φi(X)` by applying the axiom
   `∀ Z . αi(Z) → •βi(Z)` to `Φ(X)`.
1. If we can't apply one of the axioms, the algorithm fails.
1. We ignore all the the axioms where the result was `⊥`.
1. Let us reorder the axioms so that the result was not `⊥` exactly for
   axioms `1..b`.
1. If `b = 0` then the algorithm fails.
1. Let `Φr(X) = Φ(X) ∧ (¬∃ Y . α1(Y)) ∧ ... ∧ (¬∃ Y . αb(Y))`.
1. If `Φr(X)` is not `⊥` then the algorithm fails.
1. We restart the algorithm with
   `φ = φ2 ∨ φ3 ∨ ... ∨ φn ∨ Φ1(X) ∨ Φ2(X) ∨ ... ∨ Φb(X)`.

Algorithm soundness
-------------------

```
∀ X . φ(X) → allpath ∃ Y . ψ(X, Y)
```



