About
-----

Recipes to build the official minos images for the [vagrant](https://www.vagrantup.com/) platform:

| Core                                                           | Desktop                                                              |
| -------------------------------------------------------------- | -------------------------------------------------------------------- |
| [core-14.04](https://app.vagrantup.com/minos/boxes/core-14.04) | [desktop-14.04](https://app.vagrantup.com/minos/boxes/desktop-14.04) |
| [core-16.04](https://app.vagrantup.com/minos/boxes/core-16.04) | [desktop-16.04](https://app.vagrantup.com/minos/boxes/desktop-16.04) |
| [core-18.04](https://app.vagrantup.com/minos/boxes/core-18.04) | [desktop-18.04](https://app.vagrantup.com/minos/boxes/desktop-18.04) |

<!--<p align="center">-->
  <!--<a href="https://app.vagrantup.com/minos" target="_blank">-->
    <!--<img src="https://github.com/minos-org/packers/blob/master/minos-images-table.png?raw=true" alt="minos image table"/>-->
  <!--</a>-->
<!--</p>-->

Usage
-----

    $ packer build -on-error=ask minos-core-18.04-vbox.json
    $ vagrant box add minos-core-18.04 core-18.04.box
    $ vagrant init minos-core-18.04 && vagrant up

Dependencies
------------

- [Packer](https://www.vagrantup.com/)
- [Virtualbox](https://www.virtualbox.org)
