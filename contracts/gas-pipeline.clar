;; Gas Pipeline Safety Inspection Contract
;; Monitors natural gas infrastructure for leaks and maintenance needs

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-INPUT (err u201))
(define-constant ERR-PIPELINE-NOT-FOUND (err u202))
(define-constant ERR-ALREADY-EXISTS (err u203))

;; Data Variables
(define-data-var next-pipeline-id uint u1)
(define-data-var pressure-threshold uint u1000)
(define-data-var leak-detection-sensitivity uint u10)

;; Data Maps
(define-map pipelines uint {
    name: (string-ascii 50),
    location: (string-ascii 100),
    diameter-inches: uint,
    length-miles: uint,
    max-pressure: uint,
    installation-date: uint,
    operator: principal,
    status: (string-ascii 20)
})

(define-map pipeline-readings uint {
    pressure-psi: uint,
    flow-rate: uint,
    temperature: uint,
    leak-detected: bool,
    timestamp: uint
})

(define-map inspection-records uint {
    pipeline-id: uint,
    inspection-date: uint,
    inspector: principal,
    inspection-type: (string-ascii 30),
    findings: (string-ascii 200),
    passed: bool
})

(define-map emergency-alerts uint {
    pipeline-id: uint,
    alert-type: (string-ascii 30),
    severity: uint,
    timestamp: uint,
    resolved: bool
})

(define-map authorized-inspectors principal bool)

;; Authorization Functions
(define-public (add-inspector (inspector principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-inspectors inspector true))
    )
)

(define-public (remove-inspector (inspector principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-delete authorized-inspectors inspector))
    )
)

;; Pipeline Management Functions
(define-public (register-pipeline (name (string-ascii 50)) (location (string-ascii 100)) (diameter uint) (length uint) (max-pressure uint))
    (let ((pipeline-id (var-get next-pipeline-id)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-inspectors tx-sender))) ERR-NOT-AUTHORIZED)
        (asserts! (and (> diameter u0) (> length u0) (> max-pressure u0)) ERR-INVALID-INPUT)
        (asserts! (is-none (map-get? pipelines pipeline-id)) ERR-ALREADY-EXISTS)
        (map-set pipelines pipeline-id {
            name: name,
            location: location,
            diameter-inches: diameter,
            length-miles: length,
            max-pressure: max-pressure,
            installation-date: block-height,
            operator: tx-sender,
            status: "operational"
        })
        (var-set next-pipeline-id (+ pipeline-id u1))
        (ok pipeline-id)
    )
)

(define-public (record-pipeline-reading (pipeline-id uint) (pressure uint) (flow-rate uint) (temperature uint) (leak-detected bool))
    (let ((pipeline (unwrap! (map-get? pipelines pipeline-id) ERR-PIPELINE-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get operator pipeline))) ERR-NOT-AUTHORIZED)
        (asserts! (and (> pressure u0) (> flow-rate u0)) ERR-INVALID-INPUT)
        (asserts! (<= pressure (get max-pressure pipeline)) ERR-INVALID-INPUT)
        (map-set pipeline-readings pipeline-id {
            pressure-psi: pressure,
            flow-rate: flow-rate,
            temperature: temperature,
            leak-detected: leak-detected,
            timestamp: block-height
        })
        ;; Create emergency alert if leak detected
        (if leak-detected
            (map-set emergency-alerts pipeline-id {
                pipeline-id: pipeline-id,
                alert-type: "leak-detected",
                severity: u5,
                timestamp: block-height,
                resolved: false
            })
            true
        )
        (ok true)
    )
)

(define-public (conduct-inspection (pipeline-id uint) (inspection-type (string-ascii 30)) (findings (string-ascii 200)) (passed bool))
    (let ((pipeline (unwrap! (map-get? pipelines pipeline-id) ERR-PIPELINE-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-inspectors tx-sender))) ERR-NOT-AUTHORIZED)
        (map-set inspection-records pipeline-id {
            pipeline-id: pipeline-id,
            inspection-date: block-height,
            inspector: tx-sender,
            inspection-type: inspection-type,
            findings: findings,
            passed: passed
        })
        ;; Update pipeline status based on inspection
        (map-set pipelines pipeline-id (merge pipeline {
            status: (if passed "operational" "maintenance-required")
        }))
        (ok true)
    )
)

(define-public (create-emergency-alert (pipeline-id uint) (alert-type (string-ascii 30)) (severity uint))
    (let ((pipeline (unwrap! (map-get? pipelines pipeline-id) ERR-PIPELINE-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get operator pipeline))) ERR-NOT-AUTHORIZED)
        (asserts! (and (> severity u0) (<= severity u5)) ERR-INVALID-INPUT)
        (map-set emergency-alerts pipeline-id {
            pipeline-id: pipeline-id,
            alert-type: alert-type,
            severity: severity,
            timestamp: block-height,
            resolved: false
        })
        (ok true)
    )
)

(define-public (resolve-emergency-alert (pipeline-id uint))
    (let ((alert (unwrap! (map-get? emergency-alerts pipeline-id) ERR-PIPELINE-NOT-FOUND)))
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (default-to false (map-get? authorized-inspectors tx-sender))) ERR-NOT-AUTHORIZED)
        (map-set emergency-alerts pipeline-id (merge alert { resolved: true }))
        (ok true)
    )
)

;; Read-only Functions
(define-read-only (get-pipeline (pipeline-id uint))
    (map-get? pipelines pipeline-id)
)

(define-read-only (get-pipeline-reading (pipeline-id uint))
    (map-get? pipeline-readings pipeline-id)
)

(define-read-only (get-inspection-record (pipeline-id uint))
    (map-get? inspection-records pipeline-id)
)

(define-read-only (get-emergency-alert (pipeline-id uint))
    (map-get? emergency-alerts pipeline-id)
)

(define-read-only (check-pipeline-safety (pipeline-id uint))
    (let ((pipeline (unwrap! (map-get? pipelines pipeline-id) ERR-PIPELINE-NOT-FOUND))
          (reading (map-get? pipeline-readings pipeline-id))
          (alert (map-get? emergency-alerts pipeline-id)))
        (if (is-some reading)
            (let ((current-reading (unwrap-panic reading)))
                (ok {
                    pipeline-id: pipeline-id,
                    status: (get status pipeline),
                    pressure-normal: (< (get pressure-psi current-reading) (get max-pressure pipeline)),
                    leak-detected: (get leak-detected current-reading),
                    has-active-alert: (if (is-some alert) (not (get resolved (unwrap-panic alert))) false),
                    needs-inspection: (> (- block-height (get installation-date pipeline)) u2000)
                })
            )
            (ok {
                pipeline-id: pipeline-id,
                status: "no-data",
                pressure-normal: false,
                leak-detected: false,
                has-active-alert: false,
                needs-inspection: true
            })
        )
    )
)

(define-read-only (is-authorized-inspector (inspector principal))
    (or (is-eq inspector CONTRACT-OWNER) (default-to false (map-get? authorized-inspectors inspector)))
)
