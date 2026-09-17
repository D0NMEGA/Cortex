# Neuralink internship postings, read 2026-09-17

**Why this file exists.** Milestone v1.1 targets an onsite conversation with Neuralink engineers on
2026-09-18. These are the three postings that bear on what Cortex is, captured verbatim so the
walkthrough in Phase 12 maps to what the roles actually ask for rather than to a recollection of
them.

**Provenance.** Fetched 2026-09-17 from the Greenhouse board API,
`https://boards-api.greenhouse.io/v1/boards/neuralink/jobs/<id>`, which is the same source that
backs the public listings at `neuralink.com/careers`. HTML stripped to text, otherwise unedited.
Job ids: 6594422003 (SWE, BCI Applications), 6594261003 (ML Engineer), 7483748003 (Neuroengineer).
Postings change without notice; re-fetch rather than trusting this snapshot after the onsite.

## Requirement-to-evidence crosswalk

Strongest matches first. Every Cortex number below is already committed and carries its own
evidence artifact; nothing here is new work.

| Posting requirement (verbatim) | Role | Cortex evidence |
|---|---|---|
| "low latency concurrency programming, memory management and networking" | SWE/BCI | pthread `QOS_CLASS_USER_INTERACTIVE` hot path, loom-verified lock-free SPSC ring with Release/Acquire and no SeqCst, 128-byte cache-line padding, POSIX shm plus `kqueue`/`recvmsg`, `mach_msg` FD passing, ARC-free and Foundation-free hot path enforced by `hotpath-policy.sh` |
| "Fluent in programming languages such as Swift, Objective-C, Kotlin or Java" | SWE/BCI | 18,816 lines of Swift 6.2 under `SWIFT_STRICT_CONCURRENCY: complete` |
| "Experience with native (desktop/Android/iOS) preferred" | SWE/BCI | CortexMac (native AppKit, explicitly not Catalyst) and CortexiOS, both building under Xcode 26.3 |
| "delivering high-impact projects to users or businesses with clear metrics and fast iteration cycle" | SWE/BCI | Every published number is committed as a `*-evidence.md` with machine, pinned wheel versions, seed and runbook |
| "Design and implement algorithms to decode brain activity" | SWE/BCI | NDT1 encoder plus ReFIT-Kalman with Gilja-2012 intent rotation |
| "develop novel neural decoders to increase control speed and accuracy" | ML | NDT1 at 1,292,544 params, held-out co-bps 0.4096, pooled held-out velocity R2 0.4238 over 56,943 bins |
| "analyzing complex datasets, driving insights, and communicating results in a simple and clear way" | ML | The published 0 of 1,025 negative plus the leave-one-session-out transfer result |
| "Experience working with time series or unstructured data" | ML | 20 ms binned spike trains, 285,359 bins across four sessions |
| "A strong understanding of the scientific method" | Neuro | `10-PREREGISTRATION.md`, which committed the disposition of a zero before any hit count existed |
| "in-vivo electrophysiology, particularly awake-behaving recordings in non-human primates (NHP), and/or closed-loop brain-computer interfaces" | Neuro | O'Doherty/Makin Indy is awake-behaving NHP M1; the webgrid replay is the closed-loop surface |
| "neural decoding, particularly in the domains of movement or speech" | Neuro | M1 population to hand velocity |
| "Fluency with Python for data analysis" | Neuro | 17,690 lines of Python in the `Decoder/` uv subsystem |

## Honest gaps, recorded rather than papered over

- **Manifold analysis of neural population dynamics** (Neuroengineer, preferred). The repo has no
  PCA, jPCA, participation-ratio or latent-dynamics analysis of the M1 population at all. This is a
  real gap against that posting. It was considered for v1.1 and deliberately cut for time; it is a
  candidate for the next milestone.
- **fMRI experimental design** (Neuroengineer, preferred). Not applicable to this artifact and not
  claimed.
- **"2+ years of academic or industry experience"** (Neuroengineer, required). The softest fit of
  the three postings.
- **Full-stack development** (SWE/BCI, required). Cortex is native client and systems work with no
  server tier. Not claimed as full-stack.

---

## [SWE-BCI-APPS] Software Engineer Intern, BCI Applications

Location: Austin, Texas, United States; South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/6594422003
Fetched: 2026-09-17 (Greenhouse board API, boards-api.greenhouse.io/v1/boards/neuralink)

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:</strong></p>
<p>The Brain Computer Interface (BCI) Applications Team is responsible for delivering a product that gives people with paralysis the ability to control computers, phones, gaming consoles, and robotic arms with their minds at the same speed and functionality level as able-bodied people can. In addition,the team is also working on restoring speech to mute individuals, this will also open the option for direct and natural silent communication with AI agents.&nbsp; The team works closely with the PRIME clinical study patients which allows them fast and direct feedback about new features from users. The work in the team is multidisciplinary and team members have diverse backgrounds in software engineers, design engineering, ML engineering and neuro-engineering.</p>
<p><strong>Job Description and Responsibilities:</strong></p>
<p>As a Software Engineer Intern&nbsp; in the BCI team, you will collaborate with our users, specifically clinical trial participants, to comprehend their requirements and engineer brain-computer interface software systems that deliver exceptional user experiences. You will take the lead in creating innovative applications, implementing new features, and resolving existing issues to enhance the overall functionality of the software. Additionally, you will be expected to:</p>
<ul>
<li>Develop, test, and validate software systems</li>
<li>Work with cross-functional teams to design new BCI functionalities and novel computer user interfaces</li>
<li>Work with study participants to iterate on and further refine the software</li>
<li>Design and implement algorithms to decode brain activity</li>
<li>Design user experiences centered around brain control</li>
</ul>
<p><strong>Required Qualifications:</strong><strong><br></strong></p>
<ul>
<li>Strong experience with full-stack development&nbsp;</li>
<li>Fluent in programming languages such as Swift, Objective-C, Kotlin or Java</li>
<li>Experience in architecting elegant, maintainable, performant and reliable user facing software applications&nbsp;</li>
<li>Evidence in delivering high-impact projects to users or businesses with clear metrics and fast iteration cycle</li>
<li>Evidence of exceptional ability in engineering</li>
<li>Strong understanding of engineering first principles</li>
<li>You are resourceful, flexible, and adaptable; no task is too big or too small</li>
<li>Excellent communication and collaboration skills</li>
<li>Currently pursuing a Bachelor’s degree in Computer Science or a related field&nbsp;</li>
</ul>
<p><strong>Preferred Qualifications:</strong></p>
<ul>
<li>Experience with native (desktop/ Android/ iOS) preferred&nbsp;</li>
<li>Strong experience in operating system knowledge in low latency concurrency programming, memory management and networking</li>
</ul>
<div class="description">
<div class="description">
<p><strong>Pay Transparency:</strong></p>
<p>Based on California law, the following details are for California individuals only.</p>
</div>
<div class="title"><strong>California Hourly Rate:&nbsp;</strong></div>
<div class="pay-range">&nbsp;</div>
<div class="pay-range">$35/Hr USD</div>
</div><div class="content-conclusion"><div>
<p><strong>What We Offer:</strong></p>
<p>Full-time employees are eligible for the following benefits listed below.</p>
<ul>
<li>An opportunity to change the world and work with some of the smartest and most talented experts from different fields</li>
<li>Growth potential; we rapidly advance team members who have an outsized impact</li>
<li>Excellent medical, dental, and vision insurance through a PPO plan</li>
<li>Paid holidays</li>
<li>Commuter benefits</li>
<li>Meals provided</li>
<li>Equity (RSUs) <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>401(k) plan <em>*Interns initially excluded until they work 1,000 hours</em></li>
<li>Parental leave <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>Flexible time off <em>*Temporary Employees &amp; Interns excluded</em></li>
</ul>
</div></div>

---

## [ML-ENG] Machine Learning Engineer Intern

Location: South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/6594261003
Fetched: 2026-09-17 (Greenhouse board API, boards-api.greenhouse.io/v1/boards/neuralink)

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:</strong></p>
<p>The Brain Computer Interface (BCI) Applications Team is responsible for delivering a product that gives people with paralysis the ability to control computers, phones, gaming consoles, and robotic arms with their minds at the same speed and functionality level as able-bodied people can. Furthermore, the team is focused on restoring speech for mute individuals and enabling direct, natural silent communication with AI agents.&nbsp; In this role, you’ll work with neuroscientists, physicians, software engineers, and electrical engineers to develop the next-generation human-ready Brain-Computer Interface (BCI).&nbsp;</p>
<p><strong>Job Description and Responsibilities:</strong></p>
<p>We are hiring a Machine Learning Engineer Intern to develop novel neural decoders to increase control speed and accuracy, improve reliability, and expand functionality of BCIs. You will play a critical role in developing machine learning solutions and driving the successful execution of projects to achieve mission critical goals. You’ll work with cross-functional teams to design new BCI functionalities and novel computer user interfaces.</p>
<p><strong>Required Qualifications: </strong><strong><br></strong></p>
<ul>
<li>Evidence in delivering high-impact projects either in academia or industry</li>
<li>Prior experience designing and building Machine Learning models</li>
<li>Deep understanding of machine learning concepts and fundamentals</li>
<li>Experience in analyzing complex datasets, driving insights, and communicating results in a simple and clear way to both technical and non-technical stakeholders</li>
<li>Excellent communication and collaboration skills</li>
<li>Strong coding skills, with a focus on clean, efficient, and scalable code development</li>
</ul>
<p><strong>Preferred Qualifications:</strong></p>
<ul>
<li>Experience working with time series or unstructured data</li>
</ul>
<div class="description">
<div class="description">
<p><strong>Expected Compensation:</strong></p>
<p>The anticipated hourly rate for this position is listed below.</p>
</div>
<div class="title"><strong>California Hourly Rate:&nbsp;</strong></div>
<div class="pay-range">$35/Hr USD</div>
</div><div class="content-conclusion"><div>
<p><strong>What We Offer:</strong></p>
<p>Full-time employees are eligible for the following benefits listed below.</p>
<ul>
<li>An opportunity to change the world and work with some of the smartest and most talented experts from different fields</li>
<li>Growth potential; we rapidly advance team members who have an outsized impact</li>
<li>Excellent medical, dental, and vision insurance through a PPO plan</li>
<li>Paid holidays</li>
<li>Commuter benefits</li>
<li>Meals provided</li>
<li>Equity (RSUs) <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>401(k) plan <em>*Interns initially excluded until they work 1,000 hours</em></li>
<li>Parental leave <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>Flexible time off <em>*Temporary Employees &amp; Interns excluded</em></li>
</ul>
</div></div>

---

## [NEUROENG] Neuroengineer Intern

Location: South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/7483748003
Fetched: 2026-09-17 (Greenhouse board API, boards-api.greenhouse.io/v1/boards/neuralink)

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:</strong></p>
<p>The Next Gen team at Neuralink is developing the next generation of brain-computer interfaces. We are laying the groundwork for intuitive, high-dimensional, and bidirectional interfaces between brains and machines, with the goal of helping people challenged by a variety of neurological disorders and conditions. Our team consists of scientists and engineers, working closely together to define the engineering requirements for these future products. As a Neuroengineer Intern on this team, you will contribute across a wide range of projects, from designing novel experimental preparations, to interpreting neural signals and behavioral data, to developing novel BCI paradigms. Successful candidates will be highly adaptable, able to deploy their core technical and creative skills to tackle a wide range of problems, and have a keen sense of urgency.&nbsp;</p>
<p><strong>Job Description and Responsibilities:</strong></p>
<ul>
<li>Investigate and map neural correlates of sensory and internally-generated states.</li>
<li>Build and iterate on advanced machine learning architectures to map neural activity to complex, multi-dimensional outputs.</li>
<li>Design, execute, interpret, and communicate the results of experiments, ranging from non-human primate (NHP) electrophysiology to human fMRI studies.</li>
<li>Present results in a fast-paced, highly collaborative setting.</li>
</ul>
<p><strong>Required Qualifications:&nbsp;</strong></p>
<ul>
<li>Evidence of exceptional ability in neuroscience, machine learning, biomedical engineering, or a related field</li>
<li>2+ years of academic or industry experience</li>
<li>A strong understanding of the scientific method and engineering first principles</li>
<li>Fluency with Python for data analysis</li>
</ul>
<p><strong>Preferred Qualifications:</strong><strong>&nbsp;</strong></p>
<ul>
<li>Experience with modern machine learning, including LLMs, LLM interpretability, and generative models.</li>
<li>Expertise in analyzing neural population dynamics and applying manifold analysis techniques to high-dimensional neural data.</li>
<li>Strong background in neural decoding, particularly in the domains of movement or speech.</li>
<li>Experience with human fMRI experimental design, execution, and fMRI data analysis.</li>
<li>Experience with in-vivo electrophysiology, particularly awake-behaving recordings in non-human primates (NHP), and/or closed-loop brain-computer interfaces.</li>
</ul>
<div class="description">
<div class="description">
<p><strong>Pay Transparency:</strong></p>
<p>Based on California law, the following details are for California individuals only.</p>
</div>
<div class="title"><strong>California Hourly Rate:&nbsp;</strong></div>
<div class="pay-range">$35/Hr USD</div>
</div><div class="content-conclusion"><div>
<p><strong>What We Offer:</strong></p>
<p>Full-time employees are eligible for the following benefits listed below.</p>
<ul>
<li>An opportunity to change the world and work with some of the smartest and most talented experts from different fields</li>
<li>Growth potential; we rapidly advance team members who have an outsized impact</li>
<li>Excellent medical, dental, and vision insurance through a PPO plan</li>
<li>Paid holidays</li>
<li>Commuter benefits</li>
<li>Meals provided</li>
<li>Equity (RSUs) <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>401(k) plan <em>*Interns initially excluded until they work 1,000 hours</em></li>
<li>Parental leave <em>*Temporary Employees &amp; Interns excluded</em></li>
<li>Flexible time off <em>*Temporary Employees &amp; Interns excluded</em></li>
</ul>
</div></div>
