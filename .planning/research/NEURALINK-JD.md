# Neuralink internship postings, read 2026-09-17

**Why this file exists.** Milestone v1.1 targets an onsite with Neuralink engineers on 2026-09-18.
All seven open internship postings are captured verbatim below so the walkthrough maps to what the
roles actually ask for rather than to a recollection of them.

**Provenance.** Fetched 2026-09-17 from the Greenhouse board API,
`https://boards-api.greenhouse.io/v1/boards/neuralink/jobs/<id>`, the same source backing the public
listings at `neuralink.com/careers`. HTML stripped to text, otherwise unedited. The user holds PDF
captures of the same seven at `~/Downloads/NeuralinkInternships/`. Postings change without notice;
re-fetch rather than trusting this snapshot.

## The headline: Rust is named in three of seven

The single most under-weighted fit. `Packages/CortexRing` is an in-house lock-free SPSC ring in
Rust, chosen over `rtrb` specifically so it could be model-checked with `loom` (D-R3), bridged to
Swift through a `cbindgen` header and an `.xcframework` with a CI drift gate. Three postings name
Rust in their required qualifications:

- SWE Implant: "Fluent in Python and C or Rust"
- SWE Robotics: "writing performant applications in a system language like C, C++, and Rust"
- SWE Infrastructure: Rust heads the listed tech stack

Cortex has Rust, C (`cortex_shm.h` with a compile-time `_Static_assert`), Python (17,690 lines) and
Swift (18,816 lines) in one artifact, with the Rust component being the one carrying a formal
concurrency proof. Lead with the loom proof when Rust comes up; it is the least common thing in the
repo.

## Requirement-to-evidence crosswalk

Strongest fits first. Every Cortex number cited is committed with its own evidence artifact.

| Posting requirement (verbatim) | Role | Cortex evidence |
|---|---|---|
| "low latency concurrency programming, memory management and networking" | SWE/BCI | pthread `QOS_CLASS_USER_INTERACTIVE` hot path, loom-verified lock-free SPSC ring with Release/Acquire and no SeqCst, 128-byte cache-line padding, POSIX shm plus `kqueue`/`recvmsg`, `mach_msg` FD passing, ARC-free and Foundation-free hot path enforced by `hotpath-policy.sh` |
| "Fluent in Swift, Objective-C, Kotlin or Java" | SWE/BCI | 18,816 lines of Swift 6.2 under `SWIFT_STRICT_CONCURRENCY: complete` |
| "native (desktop/Android/iOS) preferred" | SWE/BCI | CortexMac (native AppKit, explicitly not Catalyst) and CortexiOS, both building under Xcode 26.3 |
| "clear metrics and fast iteration cycle" | SWE/BCI | Every published number committed as a `*-evidence.md` with machine, pinned wheel versions, seed and runbook |
| "Design and implement algorithms to decode brain activity" | SWE/BCI | NDT1 encoder, ridge baseline, ReFIT-Kalman with Gilja-2012 intent rotation |
| "Fluent in Python and C or Rust" | SWE/Implant | Rust `cortex_ring` crate, C `cortex_shm.h`, Python `Decoder/` subsystem |
| "performant applications in a system language like C, C++, and Rust" | SWE/Robotics | Same, plus the `cbindgen` FFI boundary and its CI drift gate |
| "intuition for what matters in a production system (vs. research-grade)" | SWE/Implant | Twelve `*-policy.sh` CI gates, four with adversarial `--self-test` corpora proven to bite |
| "mission-critical and safety-critical systems" | SWE/Robotics | Compile-time invariants over runtime checks: `_Static_assert` on the shm name length makes the Darwin `PSHMNAMLEN` limit structurally unviolatable |
| "Enhancing developer experience with robust tooling and build-system infrastructure" | SWE/Infra | XcodeGen single-source project topology, 12 CI gates, negative controls, reproducible `uv` Python subsystem |
| "novel neural decoders to increase control speed and accuracy" | ML | NDT1 1,292,544 params, held-out co-bps 0.4096, pooled held-out velocity R2 0.4238 |
| "analyzing complex datasets, driving insights, and communicating results in a simple and clear way" | ML | The published 0 of 1,025 negative, the LOSO transfer result, and the decode-gap decomposition in `11-decode-gap-evidence.md` |
| "time series or unstructured data" | ML | 20 ms binned spike trains, 285,359 bins across four sessions |
| "A strong understanding of the scientific method" | Neuro | `10-PREREGISTRATION.md`, which committed the disposition of a zero before any hit count existed |
| "awake-behaving recordings in non-human primates (NHP), and/or closed-loop brain-computer interfaces" | Neuro | O'Doherty/Makin Indy is awake-behaving NHP M1; the webgrid replay is the closed-loop surface, disclosed as open-loop |
| "neural decoding, particularly movement or speech" | Neuro | M1 population to hand velocity |
| "Fluency with Python for data analysis" | Neuro | 17,690 lines of Python |

## Honest gaps, recorded rather than papered over

- **Manifold analysis of neural population dynamics** (Neuroengineer, preferred). The repo has no
  PCA, jPCA, participation-ratio or latent-dynamics analysis. A real gap, deliberately cut from
  v1.1 for time, and the first candidate for v1.2.
- **Full-stack / Rails / React** (SWE Internal Apps, required; SWE/BCI, required). Cortex is native
  client and systems work with no server tier. Not claimed. Internal Apps is the weakest of the
  seven fits.
- **Kubernetes, Terraform, Bazel, Nix, AWS** (SWE Infrastructure). Not in this artifact. The CI and
  build-system tooling story transfers; the cloud stack does not.
- **Computer vision, kinematics, motion planning, medical robots** (SWE Robotics, preferred). Not
  applicable and not claimed.
- **fMRI experimental design** (Neuroengineer, preferred). Not applicable and not claimed.
- **"2+ years of academic or industry experience"** (Neuroengineer, required).
- **Safety-critical systems experience** (SWE Implant, preferred). Cortex enforces invariants like a
  safety-critical codebase but is not one, and was never certified against any standard.

---

## [SWE-BCI-APPS] Software Engineer Intern, BCI Applications

Location: Austin, Texas, United States; South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/6594422003
Greenhouse job id: 6594422003

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
Greenhouse job id: 6594261003

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
Greenhouse job id: 7483748003

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

---

## [SWE-IMPLANT] Software Engineer Intern, Implant

Location: Austin, Texas, United States; South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/6569018003
Greenhouse job id: 6569018003

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:</strong></p>
<p>The Brain Interfaces Software Team is responsible for the end to end software stack that manages implant communication, verification, manufacturing and monitoring. We own client side SDKs and full-stack platforms that are used by various divisions within the company. We are looking for versatile engineers who are interested in architecting and implementing elegant software solutions and who thrive with the autonomy to propose creative approaches to problems.&nbsp;</p>
<p>Neuralink strives to be a meritocratic environment: we require honest and transparent communication to ensure the best ideas win out, and we believe the best solutions emerge and the best teams are created when you assemble high-performing individuals and allow them to engage in rigorous and thoughtful inquiry. We want to work with exceptional people, and, to the extent that you excel, we want you to take on more responsibility and help all of us succeed. If this speaks to you, come join us.</p>
<p><strong>Job Responsibilities:</strong></p>
<p>As a Software Engineer Intern on the Brain Interfaces Software Team, your responsibilities will encompass:<strong><br></strong></p>
<ul>
<li>Developing and improving Neuralink’s Implant and Charger SDK</li>
<li>Maintaining Neuralink’s brain interface software and firmware build tooling</li>
<li>Developing and improving Neuralink’s Implant manufacturing line acceptance software</li>
<li>Maintaining Neuralink's Implant design control verification testing software</li>
<li>Developing and improving Neuralink’s Implant recorder system</li>
<li>Developing and improving Neuralink’s Implant monitoring system</li>
</ul>
<p><strong>Required Qualifications: </strong><strong><br></strong></p>
<ul>
<li>Fluent in Python and C or Rust (don’t get hung up on this—being an exceptional software engineer matters above all)</li>
<li>Experience (and comfortable) with the Linux/Unix systems and command line</li>
<li>Evidence of exceptional ability in engineering, mathematics, or computer science</li>
<li>Strong understanding of engineering first principles</li>
<li>Strong intuition for what matters in a production system (vs. research-grade)</li>
</ul>
<p><strong>Preferred Qualifications:</strong><strong> </strong><strong><br></strong></p>
<ul>
<li>Prior experience developing software for safety-critical systems<strong><br></strong></li>
</ul>
<p><strong>About You:</strong></p>
<ul>
<li>You find large challenges exciting and enjoy discovering and defining problems as much as solving them</li>
<li>You deliver. You may enjoy thoughtful conversations about problems and perfecting design, but in the end, you know that what matters is delivering reliable solutions. (Our ultimate aim is to help people; the “right” solution doesn’t always achieve that)</li>
<li>You are mission-driven and goal-oriented in your approach to solving problems</li>
<li>You feel a sense of urgency to get things done sooner rather than later—because there is so much we, as people, can contribute to the world and accomplish in this life, it’s a shame to waste time</li>
<li>You are resourceful, flexible, and adaptable; no task is too big or too small</li>
</ul>
<div class="description">
<div class="description">
<p><strong>Pay Transparency:</strong></p>
<p>Based on California law, the following details are for California individuals only.</p>
</div>
<div class="title"><strong>Hourly Rate:&nbsp;</strong></div>
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

## [SWE-INFRA] Software Engineer Intern, Infrastructure

Location: South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/5469298003
Greenhouse job id: 5469298003

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:&nbsp;</strong></p>
<p>The Infrastructure Team builds the foundation that enables the company to operate safely, robustly, and move at light-speed. We run a mixture of cloud-based and on-prem systems and have a user base spanning from highly technically proficient engineers to non-technical scientists and doctors; but all of them need solid systems, rugged networking, and bullet-proof software to do their jobs. This role will integrate tightly with teams across the company, and span all layers of the work environment stack, from deployment of physical hardware on the manufacturing line to custom tooling built to facilitate neural recordings from implants.</p>
<p><strong>Tech Stack:</strong></p>
<ul>
<li>Rust, Python</li>
<li>Terraform</li>
<li>Bazel and Nix</li>
<li>Kubernetes</li>
<li>GitLab CI</li>
<li>AWS</li>
<li>Ubuntu, Fedora</li>
</ul>
<p><strong>Focus:</strong></p>
<ul>
<li>Developing the foundations for teams to build the software and systems required for record-breaking BCI experiences.</li>
<li>Enhancing developer experience with robust tooling and build-system infrastructure.</li>
<li>Building foundational infrastructure for HITL (hardware in the loop) testing across firmware, BCI, and robot teams.</li>
<li>Ground-up infrastructure of on-premise solutions as well as cloud architecture.</li>
<li>Foundational software engineering with a focus on serving internal software teams.</li>
</ul>
<p><strong>Qualifications:</strong><strong>&nbsp;</strong></p>
<ul>
<li>Experience using IAC tools such as Terraform, Docker, Packer, Ansible, Cloud-Init, Kickstart.</li>
<li>Working knowledge of compiled languages, ideally Rust, Go, or C/C++.</li>
<li>Working knowledge of major cryptographic protocols and authentication schemes such as TLS, x509, 802.1x, U2F, SAML.</li>
<li>Familiarity with modern Linux boot process, UEFI, TPM measured boot, Secure Boot, Systemd.</li>
<li>Systems administration experience on Windows, macOS, and Linux.</li>
<li>In-depth understanding of modern networking and common protocols.</li>
<li>Ability to architect, build, and ship 0 to 1 infrastructure quickly and efficiently.</li>
</ul>
<div class="description">
<p><strong>Expected Compensation:</strong></p>
<p>The anticipated hourly rate for this position is listed below.</p>
<p><strong>California Hourly Flat Rate:</strong><br>$35/Hr USD</p>
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

## [SWE-INTERNAL-APPS] Software Engineer Intern, Internal Apps

Location: Austin, Texas, United States; South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/6083322003
Greenhouse job id: 6083322003

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><span style="font-size: 12pt;"><strong>Team Description:</strong></span></p>
<p><span style="font-size: 12pt;">The internal apps team works closely with other teams — neuroscientists, physicists, chip designers, pathologists, and mechanical engineers — to build Neuralink's centralized data aggregation and analysis platform. This data platform collects, organizes, and visualizes a diverse set of data ranging from neural signal recordings and brain histology images to experimental and operational data. Our team owns projects that drive engineering and experimentation at Neuralink.</span></p>
<p><span style="font-size: 12pt;">We operate like an internal startup — rapidly prototyping and building software that solves problems for the company. This usually takes the form of full-stack tools, but can be any tech stack.</span></p>
<p><span style="font-size: 12pt;">We operate as a tight, high-trust team. You'll have direct ownership and the autonomy to solve hard problems, but also high expectations.</span></p>
<p><span style="font-size: 12pt;">We're moving fast to meet clinical demand and keep up with deployments. 60-hour weeks are not uncommon, and there are stretches where the pace is high. This isn't for everyone.</span></p>
<p><span style="font-size: 12pt;"><strong>Job Description and Responsibilities:</strong></span></p>
<p><span style="font-size: 12pt;">This is a high-autonomy, high-ownership internship. You will work directly alongside engineers and scientists to build software that has immediate, tangible impact on Neuralink's mission. Some days you're heads-down writing code all day. Other days you're pairing with engineers across the company to understand a new workflow and figure out how to build the right tool for it.</span></p>
<p><span style="font-size: 12pt;">We are looking for versatile software engineers who are interested in architecting and implementing elegant software solutions and thrive with the autonomy to propose creative approaches to problems.&nbsp;</span></p>
<p><span style="font-size: 12pt;">As an intern, you will work on applications to make Neuralink 100x faster, such as:<strong><br></strong></span></p>
<ul>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Data platforms to collect, organize, and visualize a diverse set of data ranging from neural signal recordings, device telemetries, surgery recordings, to experimental data</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Lab Systems software, our digital collaboration hub for all teams within the company</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">ERP software that orchestrates and tracks everything involved in designing brain-computer interfaces</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">DevOps and infrastructure to increase developer productivity</span></li>
</ul>
<p><span style="font-size: 12pt;">Neuralink strives to be, as much as possible, a meritocratic environment: we require honest and transparent communication to ensure the best ideas win out. Additionally, we believe the best solutions emerge and the best teams form when you assemble high-performing individuals with different skill sets and perspectives, and allow them to engage in rigorous and thoughtful inquiry. We want to work with exceptional people, and, to the extent that you excel, we want you to take on more responsibility and help all of us succeed. If this speaks to you, come join us!</span></p>
<p><span style="font-size: 12pt;"><strong>Required Qualifications: </strong><strong><br></strong></span></p>
<ul>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Demonstrated experience shipping a product that has been actively used, regardless of tech stack or domain</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Full-stack engineering capability (Ruby on Rails and React/TypeScript preferred, though adaptability matters more)</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Ability to design and implement simple and elegant software solutions</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Strong communication and collaborative problem-solving abilities</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Ownership mentality and comfort with ambiguity</span></li>
<li style="font-size: 12pt;"><span style="font-size: 12pt;">Understanding of how software works at a fundamental level</span></li>
</ul>
<div class="description">
<p><span style="font-size: 12pt;"><strong>Expected Compensation:</strong></span></p>
<p><span style="font-size: 12pt;">The anticipated hourly rate for this position is listed below.</span></p>
<p><span style="font-size: 12pt;"><strong>California Hourly Flat Rate:<br></strong>$35/Hr USD</span></p>
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

## [SWE-ROBOTICS] Software Engineer Intern, Robotics

Location: Austin, Texas, United States; South San Francisco, California, United States
URL: https://boards.greenhouse.io/neuralink/jobs/5469305003
Greenhouse job id: 5469305003

<div class="content-intro"><p><strong>About Neuralink:</strong></p>
<p>We are creating devices that enable a bi-directional interface with the brain. These devices allow us to restore movement to the paralyzed, restore sight to the blind, and revolutionize how humans interact with their digital world.</p></div><p><strong>Team Description:</strong><strong><br></strong></p>
<p>The Robot Software Team builds software that enables scalable neurosurgery that allows safe implantation of the N1 device, ranging from core control, sensors and perception, autonomy, surgery analytics, and more. This role tightly integrates with the robot hardware team, surgery engineering team, as well as the BCI applications team which rely on us to deliver safe and effective implantation of the N1 device.&nbsp;</p>
<p>Neuralink strives to be a meritocratic environment: we require honest and transparent communication to ensure the best ideas win out, and we believe the best solutions emerge and the best teams are created when you assemble high-performing individuals and allow them to engage in rigorous and thoughtful inquiry. We want to work with exceptional people, and, to the extent that you excel, we want you to take on more responsibility and help all of us succeed. If this speaks to you, come join us.</p>
<p><strong>Job Description and Responsibilities:</strong></p>
<p>As a Software Engineer Intern on the Robot Software Team, you will be responsible for writing software and making sure your code works on an actual surgical robot, not just simulation. Our robotics integrate actuated devices with microelectromechanical systems as well as novel surgical procedures. These applications place strong emphasis on high-precision, high-repeatability mechanical motion, as well as high reliability and fail-safe design. You will be expected to:</p>
<ul>
<li>Develop safety-critical software for the robot; you are responsible for contributing directly to surgery-ready software as an intern</li>
<li>Take ownership of a project that is integral to robot functioning from design to implementation under the guidance of a robot software team member</li>
<li>Jump on problems when they arise with a strong bias for action to support robot operation by non-software teams</li>
<li>Work across different engineering disciplines; your software may involve interactions with the mechanical, electrical, biological, and neuroscience teams</li>
</ul>
<p><strong>Required Qualifications:&nbsp;</strong></p>
<ul>
<li>Evidence of exceptional ability in engineering or computer science</li>
<li>Experience in writing performant applications in a system language like C, C++, and Rust</li>
<li>Ability to work on mission-critical and safety-critical systems</li>
<li>Strong bias for action and first principles thinking</li>
</ul>
<p><strong>Preferred Qualifications:</strong><strong>&nbsp;</strong></p>
<ul>
<li>Hands-on experience with robotics or high-reliability systems</li>
<li>Experience coding in Linux and debugging on Linux systems</li>
<li>Experience in computer vision</li>
<li>Experience in kinematics and motion planning</li>
<li>Experience working on medical robots</li>
<li>Experience working in a high-precision environment</li>
</ul>
<p><strong>Pay Transparency:</strong></p>
<p>Based on California law, the following details are for California individuals only:</p>
<p><strong>California Hourly Rate:</strong></p>
<p>$35/hr USD</p><div class="content-conclusion"><div>
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
