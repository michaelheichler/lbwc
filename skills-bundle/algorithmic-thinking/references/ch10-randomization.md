# Chapter 10: Randomization

## Key Concepts

- **Randomized Algorithms (overview)**: Algorithms that use random number generation as part of their logic. Two major categories exist: Monte Carlo and Las Vegas. Randomized algorithms can be faster and easier to design than deterministic equivalents, and in some domains no comparably fast deterministic algorithm is known.

- **Monte Carlo Algorithm**: A randomized algorithm that is always fast but may produce an incorrect answer with some small probability. The tradeoff is between number of attempts and probability of correctness. More attempts raise the probability of a correct answer but slow the algorithm. One-sided-error variants guarantee correctness for one answer type (e.g., YES) while the other answer type (NO) carries residual error probability.

- **Las Vegas Algorithm**: A randomized algorithm that is always correct but whose runtime varies. Randomization is applied to the choices the algorithm makes internally, preventing any adversary from crafting a worst-case input because the algorithm's execution path is unpredictable. Expected runtime (not worst-case) is the relevant metric.

- **One-Sided vs. Two-Sided Errors**: A Monte Carlo algorithm has one-sided errors when only one of the two possible answers can be wrong (e.g., YES is always correct when output, but NO might be wrong). Two-sided-error algorithms can be wrong in either direction.

- **Expected Runtime**: The average runtime of a Las Vegas algorithm over all possible random choices. For randomized Quicksort / Caps and Bottles, the expected runtime is O(n log n) even though the worst-case is O(n²). Algorithm designers focus on expected runtime for Las Vegas algorithms rather than worst-case runtime because the worst case is astronomically unlikely with random pivots.

- **Flavor Arrays**: Problem-specific data structure used in the Yōkan solution. For each flavor value, a sorted array stores all piece indices that have that flavor. Enables O(log n) range-count queries via binary search instead of O(n) linear scan.

- **Binary Search for Range Counting (`lowest_index`)**: A binary search variant that finds the leftmost index in a sorted array with value ≥ a threshold. Called twice on a flavor array (once with `left`, once with `right + 1`) to count elements in a range in O(log n) time.

- **Divide and Conquer with a Pivot**: The core idea behind both the Caps and Bottles solution and Quicksort. Choose one element (a cap or a pivot value), partition everything else into "smaller" and "larger" groups, match/sort the chosen element, then recursively solve both subproblems.

- **Quicksort**: A famous comparison-based sorting algorithm derived directly from the Caps and Bottles divide-and-conquer structure. A random pivot is chosen, the array is split into values smaller and larger than the pivot, the two halves are recursively sorted, and then the parts are reassembled. Expected runtime O(n log n), worst-case O(n²), but the worst case is unlikely with random pivot selection.

- **Recursion Tree**: A tree diagram that characterizes the work done at each level of a recursive algorithm. Each node holds the direct work done by that subproblem call, and summing across all nodes gives total work. For Quicksort with perfect splits, each level of the tree contributes O(n) work and there are O(log n) levels, yielding O(n log n) total.

- **Random Number Generation in C**: Using `rand() % n` to generate a random integer in [0, n-1], offset by a starting index to land in a desired range. Must seed with `srand((unsigned) time(NULL))` before first use, otherwise the same pseudo-random sequence is produced every run.

- **Probability Analysis for Attempt Count**: To determine how many random attempts a Monte Carlo algorithm needs, multiply per-attempt failure probabilities for repeated independent trials. The probability of failing all k attempts is (failure_prob)^k. Subtract from 1 to get per-query success probability, then raise to the power of the number of queries to get the probability of answering every query correctly.

- **Deterministic vs. Randomized Algorithms**: Deterministic algorithms produce the same output on the same input every run and offer 100% correctness. Randomized algorithms trade guaranteed correctness or guaranteed runtime for ease of design and often faster practical performance. For primality testing, the best randomized algorithm is O(n²), while the best deterministic is O(n⁶).

---

## Problems Covered

### Problem: Yōkan
- **Source**: DMOJ problem `dmpg15g6` (2015 Don Mills Programming Gala, Gold Division)
- **Core Idea**: Given a sequence of n candy pieces, each with a flavor, answer q queries of the form [l, r]. For each query, determine whether two friends can both be satisfied: each needs at least ⌈(r-l+1)/3⌉ pieces of the same flavor (possibly different flavors for each friend).
- **Approach**: Monte Carlo algorithm. For each query, randomly sample pieces from the slab. If the answer is YES, at least 2/3 of the slab's pieces belong to the one or two qualifying flavors, so each random sample has at least a 1/3 or 2/3 chance of landing on a qualifying flavor. Repeat up to `NUM_ATTEMPTS = 60` times for each of the two friends. To count how many pieces of a given flavor appear in the slab [l, r] efficiently, precompute a sorted flavor array for each flavor and use two `lowest_index` binary search calls: one to find the first piece of that flavor ≥ l, and one to find the first piece > r, and the difference is the count. If a flavor's count ≥ 2×threshold it satisfies both friends immediately. Otherwise track the first friend's flavor and skip it when searching for the second friend's flavor.
- **Complexity**: Preprocessing: O(n log n) to build and sort flavor arrays. Per query: O(NUM_ATTEMPTS × log n) = O(60 log n). Total: O(n + q × 60 log n). Space: O(n) for flavor arrays.
- **Key Insight**: If the answer is YES, then the pieces satisfying the friends occupy at least 2/3 of the slab. A random sample from the slab therefore has probability ≥ 2/3 of hitting a qualifying flavor for the first friend and ≥ 1/3 for the second friend. Even with per-sample probabilities as low as 1/3, 60 attempts drive the per-query failure probability to (2/3)^60 ≈ 1.7×10⁻¹¹, giving a ~99.9994% chance of answering all 200,000 queries correctly.

---

### Problem: Caps and Bottles
- **Source**: DMOJ problem `cco09p4` (2009 Canadian Computing Olympiad)
- **Core Idea**: Given n caps and n bottles where each cap fits exactly one bottle, and where caps cannot be compared to caps nor bottles to bottles, match all caps to their bottles using interactive queries. Each query asks the judge whether a specific cap is too small, a match, or too big for a specific bottle. At most 500,000 queries are allowed.
- **Approach**: Las Vegas algorithm using divide and conquer (randomized Quicksort structure). Pick a random cap from the current subproblem. Query every bottle in the subproblem against that cap to find the matching bottle and split all bottles into "smaller" and "bigger" piles (Step 2, n queries). Then query every cap against the matching bottle to split all caps into "smaller" and "bigger" piles (Step 3, n queries). Report the cap-bottle match. Recursively solve the small-cap/small-bottle and big-cap/big-bottle subproblems. Randomizing the pivot cap selection prevents adversarial worst-case inputs.
- **Complexity**: Worst-case O(n²) queries (degenerate splits), but expected O(n log n) queries. With n=10,000, this comfortably fits within the 500,000-query limit. Space: O(n log n) auxiliary arrays across recursion levels.
- **Key Insight**: Without randomization, always picking the first cap (or any fixed position) is exploitable. An adversary can arrange caps/bottles in sorted order so every chosen cap creates a maximally lopsided split (one empty subproblem, one of size n-1), resulting in O(n²) queries. A single change (replacing `cap_nums[0]` with `cap_nums[rand() % n]`) converts the algorithm to a Las Vegas algorithm where no fixed input can reliably cause poor performance.

---

## Algorithm Patterns

- **Monte Carlo Sampling with Repeated Attempts**: When a random sample from the input has a "surprisingly high" probability (at least some constant fraction) of landing on a useful element, and you need to detect or find that element quickly. Template: (1) Identify the probability `p` that a single random sample is useful (e.g., 1/3 or 2/3). (2) Determine the number of queries `q` and the target overall success probability (e.g., 1-10⁻⁶). (3) Solve for attempts `k`: you need `(1-p)^k × q < target_failure_prob`, so `k = log(target_failure_prob / q) / log(1-p)`. (4) Run `k` attempts, each picking a random element and checking it in O(log n) or O(1). Per-attempt check efficiency is critical: use precomputed sorted arrays + binary search (as in Yōkan) so each sample check is O(log n), not O(n).

- **Randomized Divide and Conquer (Las Vegas)**: When a deterministic divide-and-conquer algorithm is correct but suffers O(n²) worst-case because the fixed pivot/split choice is exploitable. Applicable to any problem with the "pick a splitter, partition into smaller/larger, recurse" structure: sorting, selection (k-th smallest), matching, etc. Template: (1) Pick a random element from the current subproblem as the pivot/splitter. (2) Partition all other elements into "less than pivot" and "greater than pivot" groups. (3) Place/report the pivot at its final position. (4) Recurse on both groups. Expected O(n log n) performance holds even for splits as lopsided as 90/10 (the logarithm base changes, but the asymptotic class does not).

- **Binary Search for Leftmost ≥ Threshold (`lowest_index`)**: Counting elements in a sorted array that fall in a range [l, r]. Call once with threshold `l` and once with threshold `r+1`, and the difference is the count. More generally, use this form of binary search whenever you need "the first index satisfying a property" rather than "the index of an exact value." Invariant: All indices `< low` hold values `< at_least`, and all indices `>= high` hold values `>= at_least`. When `low == high`, that is the answer. Initialize `low = 0`, `high = num_elements` (one past end).

- **Precomputed Inverted Index (Flavor Arrays)**: When queries ask about the count or membership of elements of a specific category within a range, and the category set is known upfront. Build one sorted array per category containing all positions of that category. Range queries then reduce to two binary searches. Construction: Single pass through input, using a per-category counter to fill preallocated arrays. Memory is allocated exactly `num_of_flavor[f]` elements for flavor `f`.

- **Seeded PRNG for Reproducibility / Variance**: Always initialize with `srand((unsigned) time(NULL))` to get different random sequences across runs. This prevents the program from being deterministically broken by a test case that was crafted against a fixed seed.

- **Recognizing When This Chapter's Techniques Apply**: Monte Carlo: The problem has a YES/NO structure where YES answers have a "large fraction" property (majority element, frequent element, large cut). Random sampling has a non-negligible per-attempt probability of witnessing the YES condition. Las Vegas / randomized pivot: You have a working recursive divide-and-conquer solution that times out only on adversarially ordered inputs. The pivot/splitter choice is the only thing that causes bad behavior. Quicksort structure: Any problem that requires sorting or ordering implicitly (matching, ranking, k-th element) where you control the comparison function or oracle.

---

## Common Pitfalls

- **Too few attempts in Monte Carlo**: 10 attempts yields ~98.2% per-query success, which sounds good but collapses to near 0% success across 200,000 queries. Always multiply per-query failure rate by the number of queries to determine if you have enough attempts. The book uses 60 attempts to achieve ~99.9994% success across all 200,000 queries.

- **Forgetting to seed the RNG**: Without `srand(time(NULL))`, `rand()` produces the same sequence every run. In competitive programming this can mean a correct-looking solution that fails on a test case designed against the default seed.

- **Off-by-one in `lowest_index`**: The `high` pointer is initialized to `num_elements` (one past the end), not `num_elements - 1`. The loop condition is `high - low >= 1`. Returning `low` (not `low - 1` or `high`) gives the correct leftmost index. Getting this wrong silently miscounts elements in range.

- **Using the first friend's flavor for the second friend**: In Yōkan, after finding `first_flavor`, the second search loop must `continue` when it randomly picks `first_flavor`, because that flavor is only prevalent enough for one friend's share.

- **Mixing up cap-is-small vs. bottle-is-big**: In Caps and Bottles Step 2, a judge response of `-1` means the cap is too small for the bottle (so the bottle is big relative to the cap, put it in `big_bottles`). In Step 3, a judge response of `-1` on `cap vs matching_bottle` means the cap is too small for the matching bottle (put it in `small_caps`). These are easy to transpose.

- **Deterministic pivot choice is exploitable**: Solution 1 of Caps and Bottles (always pick `cap_nums[0]`) is correct but O(n²) on sorted input. The fix is one line: `cap_nums[rand() % n]`. Without this change, a judge can submit sorted caps/bottles and the solution times out.

- **Quadratic memory in naive Quicksort**: The version shown allocates O(n) auxiliary arrays per recursive call. With O(log n) levels on average, total auxiliary memory is O(n log n). An in-place partition approach (discussed in Appendix B) reduces space to O(log n) stack depth plus O(1) extra memory.

- **Threshold calculation uses floating-point**: The `threshold` variable is `width / 3.0` (a `double`), not integer division. Using integer division `width / 3` would floor the threshold, potentially accepting a slab that should return NO.

---

## Connections to Other Chapters

- **Chapter 1 (Hash Tables)**: Las Vegas algorithms apply directly to hash tables. Using a single fixed hash function makes the table vulnerable to adversarial collision attacks. Random hashing (choosing the hash function randomly at startup) is a canonical Las Vegas application that prevents adversaries from crafting collision-heavy inputs.

- **Chapter 7 (Binary Search)**: The `lowest_index` function in Yōkan is a direct application of the binary search template from Chapter 7. The invariant-based approach (`low` and `high` pointers, loop condition `high - low >= 1`, returning `low`) is identical in structure to the binary search functions introduced there. The chapter explicitly references Chapter 7's "Searching for a Solution" section.

- **Chapter 7 (Cave Doors)**: The interactive judge protocol in Caps and Bottles (query → read response → report) follows the same interleaved I/O pattern introduced in Cave Doors. The chapter suggests solving a small subtask first to validate the interaction, mirroring the Cave Doors approach.

- **Chapter 8 (Heaps / Building Treaps)**: The worst-case O(n²) behavior caused by always choosing the first element as a pivot in Caps and Bottles is described as "very similar to the one on page 307 that clobbered us when solving Building Treaps." Treaps and randomized Quicksort share the insight that random element selection prevents adversarially unbalanced tree/recursion structures.

- **Chapter 7 (Binary Search on Answer)**: The broader theme of Chapter 7 (instead of computing the answer directly, guess a candidate and verify) parallels this chapter's Monte Carlo approach of guessing a flavor and verifying it via binary search. Both chapters demonstrate that indirect verification strategies can be faster than direct computation.

- **Appendix B (Caps and Bottles: In-Place Sorting)**: The book notes that the naive Quicksort / Caps and Bottles solution can be made space-efficient via in-place partitioning, a technique described in Appendix B. This is the classic Lomuto or Hoare partition scheme used in production Quicksort implementations.
