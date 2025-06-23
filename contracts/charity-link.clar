;; CharityLink - Next-Generation Philanthropic Infrastructure
;;
;; Summary: Decentralized donation ecosystem built on Bitcoin's security layer
;;
;; Description: CharityLink revolutionizes charitable giving by harnessing Bitcoin's 
;; unbreakable security through Stacks to create the world's most transparent 
;; donation platform. Our smart contract infrastructure eliminates donation opacity 
;; through cryptographic verification, automated milestone tracking, and real-time 
;; impact reporting. Every satoshi donated is tracked from source to impact, 
;; ensuring donors witness their generosity transform into measurable change while 
;; empowering organizations with streamlined operations and unshakeable credibility.
;;
;; Built for the future of giving - where transparency isn't optional, it's embedded.
;;

;; SYSTEM CONSTANTS & ERROR HANDLING

;; Contract governance
(define-data-var contract-owner principal tx-sender)

;; Comprehensive error management
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-REGISTERED (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INSUFFICIENT-FUNDS (err u103))
(define-constant ERR-BENEFICIARY-NOT-FOUND (err u104))
(define-constant ERR-UTILIZATION-NOT-FOUND (err u105))
(define-constant ERR-INVALID-INPUT (err u106))

;; Access control hierarchy
(define-constant ROLE-ADMIN u1)
(define-constant ROLE-MODERATOR u2)
(define-constant ROLE-BENEFICIARY u3)

;; CORE DATA STRUCTURES

;; User permission matrix
(define-map roles
  { user: principal }
  { role: uint }
)

;; Charitable organization registry
(define-map beneficiaries
  { id: uint }
  {
    name: (string-utf8 50),
    description: (string-utf8 255),
    target-amount: uint,
    received-amount: uint,
    status: (string-ascii 20),
  }
)

;; Donation transaction ledger
(define-map donations
  { id: uint }
  {
    donor: principal,
    beneficiary-id: uint,
    amount: uint,
    timestamp: uint,
  }
)

;; Fund utilization tracking
(define-map utilization
  { id: uint }
  {
    beneficiary-id: uint,
    milestone: uint,
    description: (string-utf8 255),
    amount: uint,
    status: (string-ascii 20),
  }
)

;; STATE MANAGEMENT

;; Global counters for unique ID generation
(define-data-var beneficiary-count uint u0)
(define-data-var donation-count uint u0)
(define-data-var utilization-count uint u0)

;; UTILITY FUNCTIONS

;; Authorization verification
(define-private (is-authorized
    (user principal)
    (required-role uint)
  )
  (let ((role-data (default-to { role: u0 } (map-get? roles { user: user }))))
    (>= (get role role-data) required-role)
  )
)

;; Milestone tracking utility
(define-private (get-last-milestone (beneficiary-id uint))
  (var-get utilization-count)
)

;; ACCESS CONTROL MANAGEMENT

;; Assign user roles with validation
(define-public (set-role
    (user principal)
    (new-role uint)
  )
  (let ((existing-role (default-to u0 (get role (map-get? roles { user: user })))))
    (if (and
        (is-eq tx-sender (var-get contract-owner))
        (<= new-role ROLE-BENEFICIARY)
        (not (is-eq user tx-sender))
        (or
          (is-eq new-role ROLE-ADMIN)
          (is-eq new-role ROLE-MODERATOR)
          (is-eq new-role ROLE-BENEFICIARY)
        )
      )
      (ok (map-set roles { user: user } { role: new-role }))
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Revoke user permissions
(define-public (remove-role (user principal))
  (if (and
      (is-eq tx-sender (var-get contract-owner))
      (is-some (map-get? roles { user: user }))
      (not (is-eq user tx-sender))
    )
    (ok (map-delete roles { user: user }))
    ERR-NOT-AUTHORIZED
  )
)

;; BENEFICIARY MANAGEMENT

;; Register new charitable organization
(define-public (register-beneficiary
    (name (string-utf8 50))
    (description (string-utf8 255))
    (target-amount uint)
  )
  (let ((beneficiary-id (+ (var-get beneficiary-count) u1)))
    (if (and
        (is-authorized tx-sender ROLE-MODERATOR)
        (> (len name) u0)
        (> (len description) u0)
        (> target-amount u0)
      )
      (begin
        (map-set beneficiaries { id: beneficiary-id } {
          name: name,
          description: description,
          target-amount: target-amount,
          received-amount: u0,
          status: "active",
        })
        (var-set beneficiary-count beneficiary-id)
        (ok beneficiary-id)
      )
      ERR-INVALID-INPUT
    )
  )
)

;; Retrieve beneficiary information
(define-read-only (get-beneficiary (id uint))
  (match (map-get? beneficiaries { id: id })
    beneficiary (ok beneficiary)
    ERR-BENEFICIARY-NOT-FOUND
  )
)

;; DONATION PROCESSING ENGINE

;; Process secure donation with blockchain verification
(define-public (donate
    (beneficiary-id uint)
    (amount uint)
  )
  (let ((beneficiary (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND)))
    (if (and
        (> amount u0)
        (< beneficiary-id (+ (var-get beneficiary-count) u1))
        (is-some (map-get? beneficiaries { id: beneficiary-id }))
      )
      (match (stx-transfer? amount tx-sender (as-contract tx-sender))
        success (begin
          (map-set beneficiaries { id: beneficiary-id }
            (merge beneficiary { received-amount: (+ (get received-amount beneficiary) amount) })
          )
          (map-set donations { id: (+ (var-get donation-count) u1) } {
            donor: tx-sender,
            beneficiary-id: beneficiary-id,
            amount: amount,
            timestamp: stacks-block-height,
          })
          (var-set donation-count (+ (var-get donation-count) u1))
          (ok true)
        )
        error
        ERR-INSUFFICIENT-FUNDS
      )
      ERR-INVALID-INPUT
    )
  )
)

;; Retrieve donation details by ID
(define-read-only (get-donation-by-id (donation-id uint))
  (match (map-get? donations { id: donation-id })
    donation (ok donation)
    ERR-NOT-FOUND
  )
)

;; Get total donation count
(define-read-only (get-donation-count)
  (ok (var-get donation-count))
)

;; FUND UTILIZATION TRACKING

;; Add new fund utilization milestone
(define-public (add-utilization
    (beneficiary-id uint)
    (description (string-utf8 255))
    (amount uint)
  )
  (let ((beneficiary (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND)))
    (if (and
        (is-authorized tx-sender ROLE-ADMIN)
        (> (len description) u0)
        (> amount u0)
        (< beneficiary-id (+ (var-get beneficiary-count) u1))
      )
      (let (
          (milestone (+ (get-last-milestone beneficiary-id) u1))
          (utilization-id (+ (var-get utilization-count) u1))
        )
        (begin
          (map-set utilization { id: utilization-id } {
            beneficiary-id: beneficiary-id,
            milestone: milestone,
            description: description,
            amount: amount,
            status: "pending",
          })
          (var-set utilization-count utilization-id)
          (ok milestone)
        )
      )
      ERR-INVALID-INPUT
    )
  )
)

;; Approve fund utilization milestone
(define-public (approve-utilization
    (utilization-id uint)
    (beneficiary-id uint)
  )
  (let (
      (utilization-entry (unwrap! (map-get? utilization { id: utilization-id })
        ERR-UTILIZATION-NOT-FOUND
      ))
      (beneficiary (unwrap! (get-beneficiary beneficiary-id) ERR-BENEFICIARY-NOT-FOUND))
    )
    (if (and
        (is-authorized tx-sender ROLE-ADMIN)
        (is-eq (get beneficiary-id utilization-entry) beneficiary-id)
        (< beneficiary-id (+ (var-get beneficiary-count) u1))
        (< utilization-id (+ (var-get utilization-count) u1))
      )
      (if (<= (get amount utilization-entry) (get received-amount beneficiary))
        (begin
          (map-set utilization { id: utilization-id }
            (merge utilization-entry { status: "approved" })
          )
          (ok true)
        )
        ERR-INSUFFICIENT-FUNDS
      )
      ERR-NOT-AUTHORIZED
    )
  )
)

;; Retrieve utilization details by ID
(define-read-only (get-utilization-by-id (utilization-id uint))
  (match (map-get? utilization { id: utilization-id })
    util (ok util)
    ERR-NOT-FOUND
  )
)

;; Get total utilization count
(define-read-only (get-utilization-count)
  (ok (var-get utilization-count))
)

;; CONTRACT INITIALIZATION

;; Initialize contract with secure defaults
(define-private (initialize-contract)
  (begin
    (map-set roles { user: tx-sender } { role: ROLE-ADMIN })
    (var-set contract-owner tx-sender)
  )
)

;; Execute initialization
(initialize-contract)
