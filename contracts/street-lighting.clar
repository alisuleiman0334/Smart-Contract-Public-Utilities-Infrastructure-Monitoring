;; Street Lighting Management Contract
;; Coordinates LED streetlight installation and energy-efficient operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-INPUT (err u401))
(define-constant ERR-LIGHT-NOT-FOUND (err u402))
(define-constant ERR-ALREADY-EXISTS (err u403))

;; Data Variables
(define-data-var next-light-id uint u1)
(define-data-var energy-efficiency-target uint u80)
(define-data-var maintenance-interval uint u2000)

;; Data Maps
(define-map street-lights uint {
    location: (string-ascii 100),
    light-type: (string-ascii 20),
    wattage: uint,
    installation-date: uint,
    last-maintenance: uint,
    operator: principal,
    status: (string-ascii 20)
})

(define-map lighting-schedule uint {
    light-id: uint,
    on-time: uint,
    off-time: uint,
    brightness-level: uint,
    adaptive-mode: bool
})

(define-map energy-consumption uint {
    daily-kwh: uint,
    monthly-kwh: uint,
    efficiency-rating: uint,
    cost-savings: uint,
    timestamp: uint
})

(define-map maintenance-records uint {
    light-id: uint,
    maintenance-date: uint,
    maintenance-type: (string-ascii 30),
    technician: principal,
    parts-replaced: (string-ascii 100),
    cost: uint
})

(define-map fault-reports uint {
    light-id: uint,
    fault-type: (string-ascii 30),
    reported-date: uint,
    reporter: principal,
    resolved: bool
})

(define-map authorized-maintenance principal bool)

;; Authorization Functions
(define-public (add-maintenance-crew (crew principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-maintenance crew true))
    )
)

(define-public (remove-maintenance-crew (crew principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-delete authorized-maintenance crew))
    )
)

;; Street Light Management Functions
(define-public (install-street-light (location (string-ascii 100)) (light-type (string-ascii 20)) (wattage uint))
    (let ((light-id (var-get next-light-id)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-maintenance tx-sender))) ERR-NOT-AUTHORIZED)
        (asserts! (and (> wattage u0) (<= wattage u500)) ERR-INVALID-INPUT)
        (asserts! (is-none (map-get? street-lights light-id)) ERR-ALREADY-EXISTS)
        (map-set street-lights light-id {
            location: location,
            light-type: light-type,
            wattage: wattage,
            installation-date: block-height,
            last-maintenance: block-height,
            operator: tx-sender,
            status: "operational"
        })
        ;; Set default lighting schedule
        (map-set lighting-schedule light-id {
            light-id: light-id,
            on-time: u1800,  ;; 6 PM
            off-time: u600,  ;; 6 AM
            brightness-level: u100,
            adaptive-mode: false
        })
        (var-set next-light-id (+ light-id u1))
        (ok light-id)
    )
)

(define-public (update-lighting-schedule (light-id uint) (on-time uint) (off-time uint) (brightness uint) (adaptive bool))
    (let ((light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get operator light))) ERR-NOT-AUTHORIZED)
        (asserts! (and (< on-time u2400) (< off-time u2400) (<= brightness u100)) ERR-INVALID-INPUT)
        (map-set lighting-schedule light-id {
            light-id: light-id,
            on-time: on-time,
            off-time: off-time,
            brightness-level: brightness,
            adaptive-mode: adaptive
        })
        (ok true)
    )
)

(define-public (record-energy-consumption (light-id uint) (daily-kwh uint) (monthly-kwh uint) (efficiency uint))
    (let ((light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get operator light))) ERR-NOT-AUTHORIZED)
        (asserts! (and (> daily-kwh u0) (> monthly-kwh u0) (<= efficiency u100)) ERR-INVALID-INPUT)
        (let ((cost-savings (if (> efficiency (var-get energy-efficiency-target))
                               (/ (* monthly-kwh (- efficiency (var-get energy-efficiency-target))) u100)
                               u0)))
            (map-set energy-consumption light-id {
                daily-kwh: daily-kwh,
                monthly-kwh: monthly-kwh,
                efficiency-rating: efficiency,
                cost-savings: cost-savings,
                timestamp: block-height
            })
        )
        (ok true)
    )
)

(define-public (perform-maintenance (light-id uint) (maintenance-type (string-ascii 30)) (parts-replaced (string-ascii 100)) (cost uint))
    (let ((light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-maintenance tx-sender))) ERR-NOT-AUTHORIZED)
        (map-set maintenance-records light-id {
            light-id: light-id,
            maintenance-date: block-height,
            maintenance-type: maintenance-type,
            technician: tx-sender,
            parts-replaced: parts-replaced,
            cost: cost
        })
        ;; Update last maintenance date
        (map-set street-lights light-id (merge light {
            last-maintenance: block-height,
            status: "operational"
        }))
        (ok true)
    )
)

(define-public (report-fault (light-id uint) (fault-type (string-ascii 30)))
    (let ((light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND)))
        (map-set fault-reports light-id {
            light-id: light-id,
            fault-type: fault-type,
            reported-date: block-height,
            reporter: tx-sender,
            resolved: false
        })
        ;; Update light status
        (map-set street-lights light-id (merge light { status: "faulty" }))
        (ok true)
    )
)

(define-public (resolve-fault (light-id uint))
    (let ((fault (unwrap! (map-get? fault-reports light-id) ERR-LIGHT-NOT-FOUND))
          (light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-maintenance tx-sender))) ERR-NOT-AUTHORIZED)
        (map-set fault-reports light-id (merge fault { resolved: true }))
        (map-set street-lights light-id (merge light { status: "operational" }))
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-street-light (light-id uint))
    (map-get? street-lights light-id)
)

(define-read-only (get-lighting-schedule (light-id uint))
    (map-get? lighting-schedule light-id)
)

(define-read-only (get-energy-consumption (light-id uint))
    (map-get? energy-consumption light-id)
)

(define-read-only (get-maintenance-record (light-id uint))
    (map-get? maintenance-records light-id)
)

(define-read-only (get-fault-report (light-id uint))
    (map-get? fault-reports light-id)
)

(define-read-only (check-light-status (light-id uint))
    (let ((light (unwrap! (map-get? street-lights light-id) ERR-LIGHT-NOT-FOUND))
          (energy (map-get? energy-consumption light-id))
          (fault (map-get? fault-reports light-id)))
        (ok {
            light-id: light-id,
            status: (get status light),
            needs-maintenance: (> (- block-height (get last-maintenance light)) (var-get maintenance-interval)),
            energy-efficient: (if (is-some energy)
                                (>= (get efficiency-rating (unwrap-panic energy)) (var-get energy-efficiency-target))
                                false),
            has-active-fault: (if (is-some fault) (not (get resolved (unwrap-panic fault))) false),
            operational-days: (- block-height (get installation-date light))
        })
    )
)

(define-read-only (is-authorized-maintenance (crew principal))
    (or (is-eq crew CONTRACT-OWNER) (default-to false (map-get? authorized-maintenance crew)))
)
