# Traffic contract — see docs/iac/gate1-design.md section 4.
# Every rule below maps 1:1 to a row in the Gate 1 security-group matrix.
# Kept in one file, separate from the module calls, so the whole contract
# is readable in one place without digging through module internals.
#
#   SG-1  Internet to ALB :80            — inline in the alb module (self-contained)
#   SG-2  ALB to Service A :3001         — below
#   SG-3  Service A to Service B :3002   — below
#   SG-4  Service B to Service C :3003   — below
#   SG-5  Internet to A/B/C directly     — implicit deny: no rule written, ever
#   SG-6  Service A to Service C         — implicit deny: no rule written, ever
#   SG-7  Service C to Service A callback — NOT implemented. See Predicted
#         Edge #1 / Scar 1 in the Gate 1 doc. The app still calls it; the
#         call fails closed until this is explicitly resolved.

# SG-2: ALB to Service A :3001
resource "aws_vpc_security_group_ingress_rule" "alb_to_service_a" {
  security_group_id            = module.service_a.security_group_id
  description                  = "SG-2: ALB to Service A :3001"
  referenced_security_group_id = module.alb.alb_security_group_id
  from_port                    = 3001
  to_port                      = 3001
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service_a" {
  security_group_id            = module.alb.alb_security_group_id
  description                  = "SG-2: ALB to Service A :3001"
  referenced_security_group_id = module.service_a.security_group_id
  from_port                    = 3001
  to_port                      = 3001
  ip_protocol                  = "tcp"
}

# SG-3: Service A to Service B :3002
resource "aws_vpc_security_group_ingress_rule" "service_a_to_service_b" {
  security_group_id            = module.service_b.security_group_id
  description                  = "SG-3: Service A to Service B :3002"
  referenced_security_group_id = module.service_a.security_group_id
  from_port                    = 3002
  to_port                      = 3002
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "service_a_to_service_b" {
  security_group_id            = module.service_a.security_group_id
  description                  = "SG-3: Service A to Service B :3002"
  referenced_security_group_id = module.service_b.security_group_id
  from_port                    = 3002
  to_port                      = 3002
  ip_protocol                  = "tcp"
}

# SG-4: Service B to Service C :3003
resource "aws_vpc_security_group_ingress_rule" "service_b_to_service_c" {
  security_group_id            = module.service_c.security_group_id
  description                  = "SG-4: Service B to Service C :3003"
  referenced_security_group_id = module.service_b.security_group_id
  from_port                    = 3003
  to_port                      = 3003
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "service_b_to_service_c" {
  security_group_id            = module.service_b.security_group_id
  description                  = "SG-4: Service B to Service C :3003"
  referenced_security_group_id = module.service_c.security_group_id
  from_port                    = 3003
  to_port                      = 3003
  ip_protocol                  = "tcp"
}
