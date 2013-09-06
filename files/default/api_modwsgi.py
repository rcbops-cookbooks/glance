from glance.openstack.common import log as logging
from glance.common import config
from paste import deploy

config_files = ['/etc/glance/glance-api-paste.ini', '/etc/glance/glance-api.conf']
config.parse_args(default_config_files=config_files)
logging.setup('glance')

conf = '/etc/glance/glance-api-paste.ini'
name = "glance-api-keystone"

application = deploy.loadapp('config:%s' % conf, name=name)
