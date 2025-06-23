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