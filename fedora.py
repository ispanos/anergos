
# May replace fedora bash script

def m(s: str):
    return s.replace("    ", "").replace("\t", "").lstrip('\n')

class cat(object):

    def __lshift__(self, other):
        pass


def vscode_repo(add: bool = True):
    # cat("file.desktop") <<  """
    #     [code]
    #     name=Visual Studio Code
    #     baseurl=https://packages.microsoft.com/yumrepos/vscode
    #     enabled=1
    #     gpgcheck=1
    #     gpgkey=https://packages.microsoft.com/keys/microsoft.asc
    # """

    content = m(
        """
        [code]
        name=Visual Studio Code
        baseurl=https://packages.microsoft.com/yumrepos/vscode
        enabled=1
        gpgcheck=1
        gpgkey=https://packages.microsoft.com/keys/microsoft.asc
    """)

    print(content)


vscode_repo()
