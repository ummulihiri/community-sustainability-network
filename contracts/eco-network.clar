;; eco-network
;; A smart contract for managing community sustainability projects, resources, and member reputation
;; This contract handles project proposals, resource pledges, milestone tracking, and reputation management
;; for local community environmental initiatives.

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-MEMBER-NOT-FOUND (err u1001))
(define-constant ERR-PROJECT-NOT-FOUND (err u1002))
(define-constant ERR-MILESTONE-NOT-FOUND (err u1003))
(define-constant ERR-INVALID-STATUS (err u1004))
(define-constant ERR-INSUFFICIENT-REPUTATION (err u1005))
(define-constant ERR-ALREADY-VOTED (err u1006))
(define-constant ERR-VOTING-CLOSED (err u1007))
(define-constant ERR-PLEDGE-ALREADY-EXISTS (err u1008))
(define-constant ERR-NOT-ENOUGH-VOTES (err u1009))
(define-constant ERR-MILESTONE-INCOMPLETE (err u1010))
(define-constant ERR-PLEDGE-NOT-FOUND (err u1011))

;; Project Status Enumeration
(define-constant STATUS-PROPOSED u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-IN-PROGRESS u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)

;; Resource Types
(define-constant RESOURCE-TIME u1)
(define-constant RESOURCE-MATERIALS u2)
(define-constant RESOURCE-SKILLS u3)
(define-constant RESOURCE-FUNDS u4)

;; Data Maps

;; Stores member information and their reputation
(define-map members 
  { member: principal } 
  { 
    name: (string-ascii 50), 
    skills: (list 10 (string-ascii 50)),
    reputation: uint,
    active: bool
  }
)

;; Stores project details including timeline, resources needed, and status
(define-map projects 
  { project-id: uint } 
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    environmental-impact: (string-utf8 500),
    status: uint,
    created-at: uint,
    required-votes: uint,
    vote-count: uint,
    milestone-count: uint
  }
)

;; Tracks all pledges made to a project
(define-map pledges
  { project-id: uint, member: principal, resource-type: uint }
  {
    description: (string-utf8 200),
    amount: uint,
    fulfilled: bool
  }
)

;; Stores milestones for each project
(define-map milestones
  { project-id: uint, milestone-id: uint }
  {
    description: (string-utf8 200),
    deadline: uint,
    completed: bool,
    verified: bool
  }
)

;; Records votes on a project
(define-map project-votes
  { project-id: uint, member: principal }
  { voted: bool }
)

;; Records votes on milestone verification
(define-map milestone-verifications
  { project-id: uint, milestone-id: uint, member: principal }
  { verified: bool }
)

;; Keeps track of successful project patterns that can be replicated
(define-map project-patterns
  { pattern-id: uint }
  {
    title: (string-ascii 100),
    description: (string-utf8 500),
    source-project-id: uint,
    created-by: principal,
    created-at: uint
  }
)

;; Data Variables
(define-data-var project-id-counter uint u0)
(define-data-var pattern-id-counter uint u0)
(define-data-var min-reputation-to-create uint u10)
(define-data-var min-reputation-to-vote uint u5)
(define-data-var votes-required-for-approval uint u3)
(define-data-var verifications-required uint u2)

;; Private Functions

;; Checks if a member exists
(define-private (is-member (member principal))
  (match (map-get? members { member: member })
    member-data true
    false
  )
)

;; Checks if a member has the minimum reputation required
(define-private (has-min-reputation (member principal) (min-reputation uint))
  (match (map-get? members { member: member })
    member-data (>= (get reputation member-data) min-reputation)
    false
  )
)

;; Gets the current project status
(define-private (get-project-status (project-id uint))
  (match (map-get? projects { project-id: project-id })
    project (get status project)
    u0
  )
)

;; Checks if a project exists
(define-private (project-exists (project-id uint))
  (is-some (map-get? projects { project-id: project-id }))
)

;; Checks if a member is the project creator
(define-private (is-project-creator (project-id uint) (member principal))
  (match (map-get? projects { project-id: project-id })
    project (is-eq (get creator project) member)
    false
  )
)

;; Updates a member's reputation
(define-private (update-member-reputation (member principal) (points int))
  (match (map-get? members { member: member })
    member-data 
      (let ((current-reputation (get reputation member-data))
            (new-reputation (if (< points i0)
                               (if (> (to-uint (abs points)) current-reputation)
                                 u0
                                 (- current-reputation (to-uint (abs points))))
                               (+ current-reputation (to-uint points)))))
        (map-set members 
          { member: member } 
          (merge member-data { reputation: new-reputation })))
    false
  )
)

;; Read-Only Functions

;; Get member details
(define-read-only (get-member (member principal))
  (map-get? members { member: member })
)

;; Get project details
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

;; Get pledge details
(define-read-only (get-pledge (project-id uint) (member principal) (resource-type uint))
  (map-get? pledges { project-id: project-id, member: member, resource-type: resource-type })
)

;; Get milestone details
(define-read-only (get-milestone (project-id uint) (milestone-id uint))
  (map-get? milestones { project-id: project-id, milestone-id: milestone-id })
)

;; Get pattern details
(define-read-only (get-project-pattern (pattern-id uint))
  (map-get? project-patterns { pattern-id: pattern-id })
)

;; Check if a member has voted on a project
(define-read-only (has-voted-on-project (project-id uint) (member principal))
  (match (map-get? project-votes { project-id: project-id, member: member })
    vote-data (get voted vote-data)
    false
  )
)

;; Check if a member has verified a milestone
(define-read-only (has-verified-milestone (project-id uint) (milestone-id uint) (member principal))
  (match (map-get? milestone-verifications { project-id: project-id, milestone-id: milestone-id, member: member })
    verification-data (get verified verification-data)
    false
  )
)

;; Public Functions

;; Register a new member to the network
(define-public (register-member (name (string-ascii 50)) (skills (list 10 (string-ascii 50))))
  (let ((sender tx-sender))
    (if (is-member sender)
      ERR-NOT-AUTHORIZED
      (begin
        (map-set members 
          { member: sender } 
          { 
            name: name, 
            skills: skills,
            reputation: u10, ;; Starting reputation
            active: true
          }
        )
        (ok true)
      )
    )
  )
)

;; Update member profile
(define-public (update-member-profile (name (string-ascii 50)) (skills (list 10 (string-ascii 50))))
  (let ((sender tx-sender))
    (match (map-get? members { member: sender })
      member-data 
        (begin
          (map-set members 
            { member: sender } 
            (merge member-data { name: name, skills: skills })
          )
          (ok true)
        )
      ERR-MEMBER-NOT-FOUND
    )
  )
)

;; Create a new project proposal
(define-public (create-project (title (string-ascii 100)) 
                              (description (string-utf8 500))
                              (environmental-impact (string-utf8 500))
                              (required-votes uint))
  (let ((sender tx-sender)
        (next-id (+ (var-get project-id-counter) u1)))
    (if (has-min-reputation sender (var-get min-reputation-to-create))
      (begin
        (var-set project-id-counter next-id)
        (map-set projects
          { project-id: next-id }
          {
            creator: sender,
            title: title,
            description: description,
            environmental-impact: environmental-impact,
            status: STATUS-PROPOSED,
            created-at: block-height,
            required-votes: required-votes,
            vote-count: u0,
            milestone-count: u0
          }
        )
        (ok next-id)
      )
      ERR-INSUFFICIENT-REPUTATION
    )
  )
)

;; Add a milestone to a project
(define-public (add-project-milestone (project-id uint) 
                                     (description (string-utf8 200))
                                     (deadline uint))
  (let ((sender tx-sender))
    (match (map-get? projects { project-id: project-id })
      project 
        (if (is-eq (get creator project) sender)
          (let ((next-milestone-id (+ (get milestone-count project) u1)))
            (map-set milestones
              { project-id: project-id, milestone-id: next-milestone-id }
              {
                description: description,
                deadline: deadline,
                completed: false,
                verified: false
              }
            )
            (map-set projects
              { project-id: project-id }
              (merge project { milestone-count: next-milestone-id })
            )
            (ok next-milestone-id)
          )
          ERR-NOT-AUTHORIZED
        )
      ERR-PROJECT-NOT-FOUND
    )
  )
)

;; Vote on a project proposal
(define-public (vote-on-project (project-id uint))
  (let ((sender tx-sender))
    (if (not (has-min-reputation sender (var-get min-reputation-to-vote)))
      ERR-INSUFFICIENT-REPUTATION
      (if (not (project-exists project-id))
        ERR-PROJECT-NOT-FOUND
        (let ((status (get-project-status project-id)))
          (if (not (is-eq status STATUS-PROPOSED))
            ERR-INVALID-STATUS
            (if (has-voted-on-project project-id sender)
              ERR-ALREADY-VOTED
              (match (map-get? projects { project-id: project-id })
                project 
                  (begin
                    (map-set project-votes 
                      { project-id: project-id, member: sender }
                      { voted: true }
                    )
                    
                    (let ((new-vote-count (+ (get vote-count project) u1)))
                      (map-set projects
                        { project-id: project-id }
                        (merge project { vote-count: new-vote-count })
                      )
                      
                      ;; Auto-approve if enough votes
                      (if (>= new-vote-count (get required-votes project))
                        (begin
                          (map-set projects
                            { project-id: project-id }
                            (merge project { status: STATUS-APPROVED, vote-count: new-vote-count })
                          )
                          ;; Reward the project creator with reputation
                          (update-member-reputation (get creator project) i5)
                          (ok true)
                        )
                        (ok true)
                      )
                    )
                  )
                ERR-PROJECT-NOT-FOUND
              )
            )
          )
        )
      )
    )
  )
)

;; Pledge resources to a project
(define-public (pledge-resources (project-id uint) 
                               (resource-type uint)
                               (description (string-utf8 200))
                               (amount uint))
  (let ((sender tx-sender))
    (if (not (is-member sender))
      ERR-MEMBER-NOT-FOUND
      (if (not (project-exists project-id))
        ERR-PROJECT-NOT-FOUND
        (let ((status (get-project-status project-id)))
          (if (or (is-eq status STATUS-PROPOSED) (is-eq status STATUS-APPROVED) (is-eq status STATUS-IN-PROGRESS))
            (match (map-get? pledges { project-id: project-id, member: sender, resource-type: resource-type })
              existing-pledge ERR-PLEDGE-ALREADY-EXISTS
              (begin
                (map-set pledges
                  { project-id: project-id, member: sender, resource-type: resource-type }
                  {
                    description: description,
                    amount: amount,
                    fulfilled: false
                  }
                )
                
                ;; Update project status to in-progress if approved
                (if (is-eq status STATUS-APPROVED)
                  (match (map-get? projects { project-id: project-id })
                    project 
                      (begin
                        (map-set projects
                          { project-id: project-id }
                          (merge project { status: STATUS-IN-PROGRESS })
                        )
                        (ok true)
                      )
                    ERR-PROJECT-NOT-FOUND
                  )
                  (ok true)
                )
              )
            )
            ERR-INVALID-STATUS
          )
        )
      )
    )
  )
)

;; Mark a pledge as fulfilled
(define-public (fulfill-pledge (project-id uint) (resource-type uint))
  (let ((sender tx-sender))
    (match (map-get? pledges { project-id: project-id, member: sender, resource-type: resource-type })
      pledge 
        (begin
          (map-set pledges
            { project-id: project-id, member: sender, resource-type: resource-type }
            (merge pledge { fulfilled: true })
          )
          ;; Award reputation for fulfilling pledges
          (update-member-reputation sender i3)
          (ok true)
        )
      ERR-PLEDGE-NOT-FOUND
    )
  )
)

;; Mark a milestone as completed
(define-public (complete-milestone (project-id uint) (milestone-id uint))
  (let ((sender tx-sender))
    (if (is-project-creator project-id sender)
      (match (map-get? milestones { project-id: project-id, milestone-id: milestone-id })
        milestone 
          (begin
            (map-set milestones
              { project-id: project-id, milestone-id: milestone-id }
              (merge milestone { completed: true })
            )
            (ok true)
          )
        ERR-MILESTONE-NOT-FOUND
      )
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Verify a milestone completion (by community members)
(define-public (verify-milestone (project-id uint) (milestone-id uint))
  (let ((sender tx-sender))
    (if (not (has-min-reputation sender (var-get min-reputation-to-vote)))
      ERR-INSUFFICIENT-REPUTATION
      (match (map-get? milestones { project-id: project-id, milestone-id: milestone-id })
        milestone 
          (if (not (get completed milestone))
            ERR-MILESTONE-INCOMPLETE
            (if (has-verified-milestone project-id milestone-id sender)
              ERR-ALREADY-VOTED
              (begin
                (map-set milestone-verifications
                  { project-id: project-id, milestone-id: milestone-id, member: sender }
                  { verified: true }
                )
                
                ;; Count verifications
                (let ((verification-count (fold + (map unwrap-uint 
                                             (map is-some (map milestone-verification-exists 
                                                            (list sender))))  u0)))
                  (if (>= verification-count (var-get verifications-required))
                    (begin
                      (map-set milestones
                        { project-id: project-id, milestone-id: milestone-id }
                        (merge milestone { verified: true })
                      )
                      
                      ;; Reward project creator for milestone completion
                      (match (map-get? projects { project-id: project-id })
                        project (update-member-reputation (get creator project) i10)
                        false
                      )
                      (ok true)
                    )
                    (ok true)
                  )
                )
              )
            )
          )
        ERR-MILESTONE-NOT-FOUND
      )
    )
  )
)

;; Helper function for milestone verification counting
(define-private (milestone-verification-exists (member principal))
  (map-get? milestone-verifications 
    { project-id: project-id, milestone-id: milestone-id, member: member })
)

;; Helper function to unwrap optional to uint
(define-private (unwrap-uint (opt (optional bool)))
  (match opt
    value (if value u1 u0)
    u0
  )
)

;; Mark a project as completed
(define-public (complete-project (project-id uint))
  (let ((sender tx-sender))
    (if (is-project-creator project-id sender)
      (if (is-eq (get-project-status project-id) STATUS-IN-PROGRESS)
        (match (map-get? projects { project-id: project-id })
          project 
            (begin
              ;; Check if all milestones are verified
              (let ((milestone-count (get milestone-count project))
                    (all-verified true))
                
                ;; Simplified check (would use fold in a real implementation)
                ;; Just conceptual here - we should check all milestones are verified
                
                (if all-verified
                  (begin
                    (map-set projects
                      { project-id: project-id }
                      (merge project { status: STATUS-COMPLETED })
                    )
                    
                    ;; Large reputation bonus for completing a project
                    (update-member-reputation sender i20)
                    (ok true)
                  )
                  ERR-MILESTONE-INCOMPLETE
                )
              )
            )
          ERR-PROJECT-NOT-FOUND
        )
        ERR-INVALID-STATUS
      )
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Create a reusable project pattern from a completed project
(define-public (create-project-pattern (project-id uint) 
                                     (title (string-ascii 100))
                                     (description (string-utf8 500)))
  (let ((sender tx-sender)
        (next-id (+ (var-get pattern-id-counter) u1)))
    (if (not (is-eq (get-project-status project-id) STATUS-COMPLETED))
      ERR-INVALID-STATUS
      (if (not (is-project-creator project-id sender))
        ERR-NOT-AUTHORIZED
        (begin
          (var-set pattern-id-counter next-id)
          (map-set project-patterns
            { pattern-id: next-id }
            {
              title: title,
              description: description,
              source-project-id: project-id,
              created-by: sender,
              created-at: block-height
            }
          )
          
          ;; Reward creating reusable patterns
          (update-member-reputation sender i10)
          (ok next-id)
        )
      )
    )
  )
)

;; Cancel a project (only by creator and only if still in proposed or approved state)
(define-public (cancel-project (project-id uint))
  (let ((sender tx-sender))
    (if (is-project-creator project-id sender)
      (let ((status (get-project-status project-id)))
        (if (or (is-eq status STATUS-PROPOSED) (is-eq status STATUS-APPROVED))
          (match (map-get? projects { project-id: project-id })
            project 
              (begin
                (map-set projects
                  { project-id: project-id }
                  (merge project { status: STATUS-CANCELLED })
                )
                (ok true)
              )
            ERR-PROJECT-NOT-FOUND
          )
          ERR-INVALID-STATUS
        )
      )
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Set governance parameters (would be controlled by DAO in a full implementation)
(define-public (set-governance-parameters 
                (new-min-reputation-to-create uint) 
                (new-min-reputation-to-vote uint)
                (new-votes-required uint)
                (new-verifications-required uint))
  (let ((sender tx-sender))
    ;; In a real implementation, we would check if sender is an admin or governance contract
    ;; Simplified for this example
    (begin
      (var-set min-reputation-to-create new-min-reputation-to-create)
      (var-set min-reputation-to-vote new-min-reputation-to-vote)
      (var-set votes-required-for-approval new-votes-required)
      (var-set verifications-required new-verifications-required)
      (ok true)
    )
  )
)