resource "alicloud_esa_site" "public" {
  count       = var.enable_esa ? 1 : 0
  site_name   = var.esa_site_name
  coverage    = "global"
  access_type = "CNAME"
  instance_id = var.esa_instance_id
  tags        = local.tags
}

resource "alicloud_esa_record" "website" {
  count       = var.enable_esa ? 1 : 0
  site_id     = alicloud_esa_site.public[0].id
  record_name = var.website_domain
  record_type = "CNAME"
  source_type = "OSS"
  host_policy = "follow_origin_domain"
  proxied     = true
  biz_name    = "web"
  ttl         = 1
  comment     = "Knora One global static website"

  data {
    value = var.website_oss_origin
  }
}

resource "alicloud_esa_record" "api" {
  count       = var.enable_esa ? 1 : 0
  site_id     = alicloud_esa_site.public[0].id
  record_name = var.api_domain
  record_type = "A/AAAA"
  proxied     = true
  biz_name    = "api"
  ttl         = 1
  comment     = "Knora One dynamic API"

  data {
    value = alicloud_instance.app.public_ip
  }
}

resource "alicloud_esa_cache_rule" "api_no_store" {
  count                     = var.enable_esa ? 1 : 0
  site_id                   = alicloud_esa_site.public[0].id
  rule_name                 = "api-and-webhooks-never-cache"
  rule_enable               = "on"
  rule                      = "http.host eq \"${var.api_domain}\""
  sequence                  = 1
  bypass_cache              = "bypass_all"
  browser_cache_mode        = "no_cache"
  edge_cache_mode           = "no_cache"
  cache_reserve_eligibility = "bypass_cache_reserve"
}

resource "alicloud_esa_http_request_header_modification_rule" "api_client_ip" {
  count       = var.enable_esa ? 1 : 0
  site_id     = alicloud_esa_site.public[0].id
  rule_name   = "api-trusted-client-ip"
  rule_enable = "on"
  rule        = "http.host eq \"${var.api_domain}\""
  sequence    = 1

  request_header_modification {
    operation = "add"
    name      = "True-Client-IP"
    type      = "dynamic"
    value     = "ip.src"
  }

  request_header_modification {
    operation = "add"
    name      = "X-Knora-Country-Code"
    type      = "dynamic"
    value     = "ip.geoip.country"
  }

  request_header_modification {
    operation = "add"
    name      = "X-Knora-ESA-Token"
    type      = "static"
    value     = var.esa_origin_header_token
  }
}
