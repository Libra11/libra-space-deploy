locals {
  direct_mail_dns_domain = "penlibra.xin"
}

resource "alicloud_alidns_record" "direct_mail_dkim" {
  domain_name = local.direct_mail_dns_domain
  rr          = "aliyun-cn-hangzhou._domainkey.mail"
  type        = "TXT"
  value       = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCvf+hNBfuaezdHd2CRj7ejkPw3oGr0sh5xx3U60gkiK7vdyXvbEbaRrzXiWaSn5XBvltf3w/Jj5xBBAWlx4V3Lxb+qIUQgHZ/onbA3XjA/zhOm8ztU2R/pKdrtvQRAE6DyTjhxaoCa2V7FS+Euuc7/GTj61EHubI8B/WqDsFb1ewIDAQAB"
  ttl         = 600
  remark      = "Knora One DirectMail DKIM"
}

resource "alicloud_alidns_record" "direct_mail_spf" {
  domain_name = local.direct_mail_dns_domain
  rr          = "mail"
  type        = "TXT"
  value       = "v=spf1 include:spf1.dm.aliyun.com -all"
  ttl         = 600
  remark      = "Knora One DirectMail SPF"
}

resource "alicloud_alidns_record" "direct_mail_dmarc" {
  domain_name = local.direct_mail_dns_domain
  rr          = "_dmarc.mail"
  type        = "TXT"
  value       = "v=DMARC1;p=none;rua=mailto:dmarc_report@service.aliyun.com"
  ttl         = 600
  remark      = "Knora One DirectMail DMARC"
}

resource "alicloud_alidns_record" "direct_mail_mx" {
  domain_name = local.direct_mail_dns_domain
  rr          = "mail"
  type        = "MX"
  value       = "mx01.dm.aliyun.com"
  priority    = 10
  ttl         = 600
  remark      = "Knora One DirectMail MX"
}
